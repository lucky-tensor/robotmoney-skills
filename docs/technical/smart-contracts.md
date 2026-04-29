# Robot Money — Smart Contract Analysis

> Reverse-engineered from the ABIs, addresses, error sets, and behavioral knowledge baked into `@robotmoney/cli` and the SKILL/reference docs in this repo. **Solidity sources are not in-tree** — this is an inferred contract spec, not a code review. Every claim below is grounded in either an ABI entry (`packages/cli/src/lib/abi.ts`), an address constant (`lib/addresses.ts`, `lib/basket/constants.ts`), an executed code path (`lib/storage-slots.ts`, `lib/basket/`), or an observed runtime error decoded by the CLI.

---

## 1. System overview

The on-chain Robot Money system is intentionally narrow at v1: one ERC-4626 vault on Base that splits USDC across three lending protocols via thin per-protocol adapters, plus a **separate** atomic basket buy/sell routed through Uniswap UniversalRouter on the client side. There is no governance contract, no upgrade proxy interface visible to the CLI, and no on-chain token whitelist mechanism.

```
                   ┌─────────────────────────────────────────────┐
                   │             RobotMoneyVault                 │
                   │           (ERC-4626, OZ Pausable)           │
                   │                                             │
                   │   asset = USDC, share = rmUSDC (6 dec)      │
                   │   tvlCap, perDepositCap, exitFeeBps=25      │
                   │   adapterCount() / getAdapterInfo(i)        │
                   └──┬───────────────┬───────────────┬──────────┘
                      │ equal-weight  │               │
                      │ (33.33% each) │               │
                ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼──────────┐
                │  Morpho   │   │  Aave V3  │   │  Compound V3   │
                │  Adapter  │   │  Adapter  │   │   Adapter      │
                └─────┬─────┘   └─────┬─────┘   └─────┬──────────┘
                      │               │               │
                ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼──────────┐
                │ Gauntlet  │   │ Aave Pool │   │   Comet        │
                │ USDC Prime│   │  (USDC)   │   │   cUSDCv3      │
                └───────────┘   └───────────┘   └────────────────┘

                              ─── separate, client-orchestrated ───

                ┌──────────────────────────────────────────────────┐
                │   Uniswap UniversalRouter (Permit2-mediated)     │
                │   V3 + V4 mixed routes for 6 basket tokens       │
                └──────────────────────────────────────────────────┘
```

The "5% basket leg" advertised on `prepare-deposit` is **not** a vault feature. The vault only knows about USDC and adapters. The basket buy is a second top-level transaction the CLI sequences alongside the vault deposit so the user *experiences* a 95/5 split. The two legs commit independently — either can land without the other.

---

## 2. Deployed contracts (Base mainnet, chain id 8453)

### 2.1 Robot Money proper

| Role | Contract | Address | Source |
|---|---|---|---|
| Vault | `RobotMoneyVault` | [`0x4f835c9f54bcf17daf9040f60cb72951ccbb49dd`](https://basescan.org/address/0x4f835c9f54bcf17daf9040f60cb72951ccbb49dd) | `ADDRESSES.base.vault` |
| Adapter | `MorphoAdapter` | [`0xa6ed7b03bc82d7c6d4ac4feb971a06550a7817e9`](https://basescan.org/address/0xa6ed7b03bc82d7c6d4ac4feb971a06550a7817e9) | `ADDRESSES.base.morphoAdapter` |
| Adapter | `AaveV3Adapter` | [`0x218695bdab0fe4f8d0a8ee590bc6f35820fc0bea`](https://basescan.org/address/0x218695bdab0fe4f8d0a8ee590bc6f35820fc0bea) | `ADDRESSES.base.aaveAdapter` |
| Adapter | `CompoundV3Adapter` | [`0x8247da22a59fce074c102431048d0ce7294c2652`](https://basescan.org/address/0x8247da22a59fce074c102431048d0ce7294c2652) | `ADDRESSES.base.compoundAdapter` |
| Admin / fee recipient | Safe multisig | [`0x88bA7364cC6cE5054981d571b33f8fb3E91475A0`](https://basescan.org/address/0x88bA7364cC6cE5054981d571b33f8fb3E91475A0) | `feeRecipient()` live read in `read.md` |

All five are referenced by the CLI; the README states "all contracts verified on BaseScan."

### 2.2 Underlying yield venues (third-party)

| Protocol | Contract on Base | Used for |
|---|---|---|
| Morpho — Gauntlet USDC Prime | `0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61` | Held immutably by `MorphoAdapter` (per comment in `addresses.ts`) |
| Aave V3 Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` | `getReserveData(USDC).currentLiquidityRate` for APY |
| Compound V3 Comet (cUSDCv3) | `0xb125E6687d4313864e53df431d5425969c15Eb2F` | `getUtilization()` + `getSupplyRate()` for APY |

### 2.3 Basket dependencies (Uniswap on Base)

| Contract | Address |
|---|---|
| UniversalRouter | `0x6fF5693b99212Da76ad316178A184AB56D299b43` |
| V4 PoolManager | `0x498581fF718922c3f8e6A244956aF099B2652b2b` |
| V4 Quoter | `0x0d5e0F971ED27FBfF6c2837bf31316121532048D` |
| V3 Factory | `0x33128a8fC17869897dcE68Ed026d694621f6FDfD` |
| V3 QuoterV2 | `0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| WETH | `0x4200000000000000000000000000000000000006` |

---

## 3. `RobotMoneyVault` interface

### 3.1 ERC-4626 + ERC-20 surface (OpenZeppelin v5)

Standard ERC-4626 in full: `asset()`, `totalAssets()`, `convertToAssets()`, `convertToShares()`, all four `preview*` (`Deposit`/`Mint`/`Withdraw`/`Redeem`), all four `max*`, plus `deposit(assets, receiver)`, `mint` is implied (not explicitly in CLI ABI but ERC-4626-mandated), `withdraw(assets, receiver, owner)`, `redeem(shares, receiver, owner)`. Standard ERC-20 (`balanceOf`, `allowance`, `decimals=6`, `symbol="rmUSDC"`, `name`, `totalSupply`).

Important behavioral note: `previewRedeem` and `previewWithdraw` return **net** USDC after the 0.25% exit fee (per `read.md` and `SKILL.md`). This is non-default OZ ERC-4626 behavior — fees are baked into the preview, which is the depositor-friendly choice but means callers should not double-subtract the fee.

### 3.2 Operational state (custom, beyond ERC-4626)

```solidity
function paused()         external view returns (bool);  // OZ Pausable
function shutdown()       external view returns (bool);  // custom permanent kill
function tvlCap()         external view returns (uint256);
function perDepositCap()  external view returns (uint256);
function exitFeeBps()     external view returns (uint256);
function feeRecipient()   external view returns (address);
```

Live values (live `get-vault` snapshot in `read.md`): `tvlCap = 100,000 USDC`, `perDepositCap = 5,000 USDC`, `exitFeeBps = 25`, `feeRecipient = 0x88bA…75A0`.

Two distinct emergency switches:

- **`paused`** — OZ `Pausable`, reversible. Reverts with `EnforcedPause` when set; `ExpectedPause` when an unpause is called while not paused. SKILL.md describes this as an *operational emergency* with withdrawals possibly still available.
- **`shutdown`** — custom, terminal. Reverts deposits with `VaultShutdown`. Withdrawals continue working.

The pair-of-switches design is meaningful: pause is a tactical brake, shutdown is graceful end-of-life. There is no `unshutdown`, ABI-wise the function only exposes the read.

### 3.3 Adapter introspection

```solidity
function adapterCount() external view returns (uint256);
function getAdapterInfo(uint256 i) external view returns (
    address adapterAddr,
    uint16  capBps,        // per-adapter ceiling in bps of TVL
    bool    active,
    uint256 currentBalance,
    uint256 targetBps      // current routing weight
);
```

Live state: 3 active adapters, each with `targetBps = 3333` (33.33%) and `capBps = 5000` for Morpho (50% per-adapter ceiling). The contract clearly distinguishes a **static cap** from a **dynamic target**: `capBps` is set at adapter registration and bounds how much the vault will ever route into one venue, while `targetBps` is computed per-deposit from the active set.

The CLI assumes `targetBps` is **dynamic equal weight across active adapters** (so 4-active = 25%, 2-active = 50%) per the `apy.weight` calculation in `read.md` and SKILL.md text. There is no setter visible for `targetBps`, which is consistent with it being derived rather than stored.

The `getAdapterInfo` return tuple ordering and types are reproduced from the ABI in `lib/abi.ts:30-45`.

### 3.4 Custom errors (vault-specific)

| Selector | When | Inferred meaning |
|---|---|---|
| `TVLCapExceeded()` | deposit pushes `totalAssets()` past `tvlCap()` | TVL gate is enforced atomically inside `deposit` |
| `PerDepositCapExceeded()` | single `deposit.assets > perDepositCap()` | Anti-whale, separate from TVL gate |
| `VaultShutdown()` | deposit while `shutdown == true` | Permanent-kill gate |
| `NoActiveAdapters()` | deposit/withdraw with zero active adapters | Routing is mandatory; no idle USDC mode |
| `InvalidFee()`, `InvalidParam()`, `InvalidCap()`, `ZeroAddress()` | admin-side setters with bad inputs | Admin write surface exists but is not in the CLI ABI |
| `EnforcedPause()`, `ExpectedPause()` | OZ Pausable | Standard |
| `ERC4626ExceededMax{Deposit,Mint,Withdraw,Redeem}` | OZ ERC-4626 | Standard; surfaces `(actor, amount, max)` |
| `ERC20Insufficient{Allowance,Balance}` | OZ ERC-20 | Standard |

The presence of `Invalid*` and `ZeroAddress` errors implies an admin write surface — `setExitFeeBps`, `setTvlCap`, `setPerDepositCap`, `setFeeRecipient`, `addAdapter`/`activateAdapter`, `pause`/`unpause`, `shutdown` are all plausible — but none are surfaced in the CLI ABI because the CLI never calls them.

### 3.5 Events

The CLI does not decode events; no event ABI is shipped. Standard ERC-4626 (`Deposit`, `Withdraw`) and ERC-20 (`Transfer`, `Approval`) are presumably present. Nothing further can be asserted from the repo.

---

## 4. Adapter contracts

The vault's interface is the only one fully exposed; the adapter contracts are referenced by address only. From observed behavior:

- Each adapter is a **per-protocol thin wrapper** holding USDC and minting/burning a per-protocol receipt (Morpho vault shares, aTokens, cUSDCv3) on behalf of the vault.
- Adapters are **immutable per-deployment** for their underlying — the comment in `addresses.ts:20-24` notes "If a new MorphoAdapter is ever deployed, update this constant or read from the adapter via `MORPHO_VAULT()` instead." This implies adapters expose a public getter for their underlying protocol contract (`MORPHO_VAULT()` on `MorphoAdapter`); equivalent functions on Aave/Compound adapters are likely (`AAVE_POOL()`, `COMET()`) but unverified.
- Adapters are **not directly user-callable** for deposit/withdraw — users always go through the vault, and the vault routes.
- APY data is *not* read from the adapter: the CLI bypasses adapters and queries `Aave V3 Pool` / `Comet` directly (`lib/morpho-apy.ts` etc.), and Morpho APY comes from Morpho's GraphQL API. So the adapter is a pure escrow + routing wedge, not a yield-reporting layer.

---

## 5. Vault mechanics in detail

### 5.1 Deposit flow

`vault.deposit(assets, receiver)`:

1. Reverts on `paused`, `shutdown`, `assets > perDepositCap`, `totalAssets + assets > tvlCap`, `activeAdapterCount == 0`.
2. Pulls `assets` USDC from `msg.sender` (requires prior `USDC.approve(vault, assets)`).
3. Computes per-adapter target as `assets / activeAdapterCount` (equal weight) and pushes USDC into each active adapter atomically — this is what the SKILL doc asserts ("atomically routes USDC across active adapters by equal weight"). With 3 active adapters and a 100 USDC deposit, that's ~33.33 each. Rounding handling is unspecified by the CLI.
4. Mints rmUSDC shares to `receiver`. Share count = `convertToShares(assets)` per OZ ERC-4626 — proportional to the current `totalAssets / totalSupply` ratio, so share price is preserved over time.

The `0.1.2` changelog entry confirms ~1.8M gas to "route across 3 adapters" in a single `deposit` call. The simulation hack documented at `lib/storage-slots.ts:1-10` (`USDC_ALLOWANCE_MAPPING_SLOT = 10`) exists because absent a `stateOverride`, the deposit simulates pre-approval and reverts at the allowance check, returning a misleadingly tiny gas estimate.

### 5.2 Withdraw / redeem flow

Two entrypoints:

- `redeem(shares, receiver, owner)` — burn N shares, return proportional USDC. `--shares max` resolves to `vault.balanceOf(owner)` client-side.
- `withdraw(assets, receiver, owner)` — burn enough shares to release exactly `assets` net USDC.

Both apply the **0.25% exit fee** (`exitFeeBps = 25`) before transferring USDC out. SKILL.md is explicit that `previewRedeem` / `previewWithdraw` return the *net* receivable amount, i.e. fees are folded into the preview — the user does not need to subtract.

The vault drains adapters proportionally on withdraw; SKILL.md notes that if a single adapter lacks liquidity, `prepare-withdraw` can fail and `prepare-redeem --shares max` is the fallback because it caps at what's actually available. This implies: withdraw uses an exact-output algorithm that requires every adapter to satisfy its share of the request, while redeem is best-effort. Solidity-side this is consistent with `withdraw` reverting on adapter shortfall vs. redeem returning whatever the proportional pull yields.

There is **no cooldown, no lock, no two-step withdrawal** — both flows are synchronous in a single transaction. This is uncommon for multi-adapter vaults (many require an unbond / claim two-step) and constrains the system's safe TVL ceiling: every withdrawal must be servable from instant liquidity in the underlying protocols, which is why launch is capped at $100k.

### 5.3 Share price accrual

- No rebasing — `balanceOf` is constant; share value grows.
- Yield accrues inside the underlying protocols (Morpho/Aave/Compound). When the vault calls `totalAssets()`, it presumably sums each adapter's `currentBalance`, which itself reads the live underlying value (Morpho share-to-asset, aToken balance, cUSDCv3 balance). So share price updates at *read time* — there is no harvest/poke required.
- This means **idle TVL is impossible** with `NoActiveAdapters` reverting on deposit; the vault refuses to hold raw USDC.

### 5.4 Fee accrual

Only the **0.25% exit fee** is visible on-chain in the ABI. The 2% annual management fee mentioned on robotmoney.net is not a vault function the CLI calls. Three plausible implementations, none confirmable from this repo:

1. Off-chain accounting: skim from harvested yield via admin transactions.
2. A `harvest()` or `accrueFees()` admin function not in the CLI ABI.
3. Continuous accrual via an internal `lastFeeAccrual` timestamp inside the adapter or vault, deducted on every read of `totalAssets()`.

The exit fee is sent to `feeRecipient()` (the Safe multisig).

---

## 6. Storage layout (only one slot is asserted)

`lib/storage-slots.ts` documents one external assumption:

> **USDC on Base is a Circle FiatTokenV2_2 proxy. The `allowed` mapping lives at storage slot 10 of the implementation.**

This is verified on-chain by the comment ("computing `keccak256(pad32(spender) ++ keccak256(pad32(owner) ++ pad32(10)))` for a known allowance and comparing `eth_getStorageAt` against `allowance(owner, spender)`"). It is used to inject a fake approval into `eth_call`'s `stateOverride` so that `vault.deposit` simulation succeeds without an actual approval landing. This is an external dependency, not Robot Money's storage.

**Robot Money's own storage layout is not asserted anywhere in this repo.** No proxy-admin slot, no implementation slot read. Whether the vault is upgradeable (UUPS / transparent / beacon) is unknown from the CLI's perspective; nothing in the ABI suggests an upgrade interface.

---

## 7. Access control & admin surface

Inferred, not directly visible:

- `feeRecipient()` returns the Safe multisig `0x88bA…75A0`. The README explicitly states "Vault is administered by a Safe multisig." This is consistent with a single-owner / `Ownable2Step` or `AccessControl`-with-DEFAULT_ADMIN model where the Safe holds the admin role.
- Setter functions (`setExitFeeBps`, `setTvlCap`, `setPerDepositCap`, `setFeeRecipient`, `pause`/`unpause`, `shutdown`, `addAdapter`/`activateAdapter` etc.) exist — implied by `InvalidFee`/`InvalidCap`/`ZeroAddress` errors — but their selectors and access control are not visible to the CLI.
- The CLI being purely read+user-write means it never has a reason to call the admin surface, hence its absence from the local ABI.

**This is a reasonable trust model for a soft launch:** caps + Safe-gated parameters + a permanent shutdown switch + Pausable. It is *not* a no-trust system; the Safe could change adapters or fees within whatever bounds the contract allows. Whether timelocks exist is unknown.

---

## 8. The basket leg (off-vault, client-orchestrated)

The basket is **not** a smart contract — it's a client-side orchestration of Uniswap calls. Specifically:

- **6 fixed tokens** with hardcoded routes in `lib/basket/constants.ts:36-108`. Pool fees, hop counts, and (for V4) hook addresses + tickSpacing are all baked into the CLI binary. There is no on-chain registry; updating the basket means publishing a new `@robotmoney/cli` version.
- **Routing is exclusively Uniswap** (V3 + V4). One V4 leg exists (ROBOT, via a Doppler dynamic-fee hook at `0xbB7784A4d481184283Ed89619A3e3ed143e1Adc0`, fee=`0x800000`/`DYNAMIC_FEE_FLAG`, tickSpacing=200). The remaining 5 are pure V3, often via WETH (USDC→WETH→TOKEN).
- **Atomic per-leg, not cross-leg.** Each `UniversalRouter.execute()` call is atomic for that one swap, and the basket-buy command bundles all 6 token buys into a single UR `execute()` call (per SKILL.md: "atomic in one `execute()` call"). However, the basket-buy `execute()` and the vault `deposit()` are **separate top-level transactions** — one can succeed and the other fail. The README architecture diagram is explicit: "vault leg + basket leg commit independently."
- **Permit2 mediation.** USDC → Permit2 (max amount, no expiration) and Permit2 → UR (max amount, 1y expiration) are auto-emitted when missing/expired. After warm-up, steady-state cost is 1 tx (deposit) for vault-only, or 2 tx (deposit + UR.execute) when basket is on.
- **Basket sells reverse the flow** with `UniversalRouter.execute()` going TOKEN→USDC. Sell flags (`--sell-all`, `--sell-percent`, `--sell-tokens`, `--sell-amounts`) are CLI-side only; nothing on-chain enforces "you can only sell what you got from this vault." Users can sell tokens they obtained anywhere.
- **Slippage default 3%** (`DEFAULT_SLIPPAGE_BPS = 300`). This is uniform across V3 and V4 dynamic-fee pools because Clanker hooks can spike fees up to 80% during volatility (per the comment in `constants.ts:115-117`). Tighter slippage on V3 legs is a known TODO.
- **Quote validity 5 min** (`QUOTE_VALIDITY_MINUTES = 5`) embedded as the UR `execute()` deadline.

---

## 9. Trust model summary

| Risk | Mitigation in current design | Residual |
|---|---|---|
| Smart contract bug | Vault is small (one ERC-4626 + thin adapters); OZ v5 base; uses `Pausable` + `shutdown` | No public audit reference in this repo; sources not in-tree |
| Adapter venue risk (Morpho/Aave/Compound) | Three adapters, equal-weight diversification | A bad day at any one venue still costs ~33% of TVL during the impact window |
| Admin abuse | Safe multisig as `feeRecipient` and (presumed) admin | No timelock visible; full setter surface unknown |
| Cap breach / griefing | `tvlCap` + `perDepositCap` + `NoActiveAdapters` revert | Soft caps are trivially low ($100k) — risk-bounded, not user-friendly |
| Stuck withdrawals | No locks; synchronous redeem; both `withdraw` and `redeem` paths | If underlying liquidity dries up, `withdraw(amount)` fails and forces `redeem(max)`; partial drains possible |
| Basket frontrunning / bad fills | 3% slippage, 5-min quote deadline, V4 dynamic-fee hooks accommodated | 3% is loose for V3 legs; basket sells use the same default |
| Wrong basket token / rugged route | Routes are hardcoded per CLI version | Only mitigation is publishing a new version; no on-chain veto |
| Key compromise | CLI never holds keys; OWS or external signer | OWS is itself novel software, separate audit surface |

---

## 10. What's *not* on-chain (gap to the website's vision)

The robotmoney.net roadmap describes a richer protocol — three buckets (50% stable / 25% agent tokens / 25% revenue-generating tokens), a `$ROBOTMONEY` governance token with weekly allocation votes, monthly weight rebalancing, bribe infrastructure, `veRM`, multi-chain. **None of this is on-chain in the contracts referenced by this repo.** The deployed system is Phase 4 of the public roadmap: a single-bucket, equal-weight, governance-free, Base-only stable-yield vault with a CLI-orchestrated agent-token sidecar.

Translating between the website's "buckets" and the deployed reality:

| Website (target) | Deployed (today) |
|---|---|
| Bucket A: stable yield (50%) | The entire vault — 95% of a deposit |
| Bucket B: agent-economy tokens (25%, governance-allocated) | The 5% basket leg — fixed 6-token list, no governance, hardcoded in CLI |
| Bucket C: revenue-generating tokens (25%) | Not implemented |
| `$ROBOTMONEY` weekly allocation vote | Not implemented |
| 2% annual management fee | Not visible in vault ABI; presumably off-chain or via an admin function not exposed |
| LP locked until 2100 | Off-vault; pertains to the `$ROBOTMONEY` token's Uniswap LP, not Robot Money's vault |

---

## 11. Open questions for source review

If/when contract sources become available, these are the things the CLI's ABI does not pin down:

1. **Adapter rebalancing.** Is `targetBps` a derived value (`active ? 1/n : 0`) or a stored value the admin can tilt? The CLI assumes the former; an `addAdapter(addr, capBps)` admin path almost certainly exists, but a `rebalance()` or `setTargetBps()` function would change the analysis.
2. **Withdraw routing algorithm.** Does `withdraw(assets, …)` pull proportionally and fail on shortfall, or pull greedily from the most-liquid adapter? SKILL.md hints at the former but isn't authoritative.
3. **Management fee accrual.** Is there a `harvest()` / `accrueFees()` / continuous-time skim, or is the 2% advertised on the website implemented purely off-chain?
4. **Upgradeability.** Proxy or immutable? No EIP-1967 read in the CLI.
5. **Adapter loss handling.** If `Comet.balanceOf(adapter)` returns less than the principal deposited, does `totalAssets()` reflect the loss linearly, or is there a high-water-mark mechanism?
6. **Reentrancy posture.** OZ ReentrancyGuard usage on `deposit`/`withdraw`/`redeem` is plausible but unverified.
7. **Adapter swap.** Can the admin replace `MorphoAdapter` with a new deployment without forcing a vault redeploy? The address-constant comment in `addresses.ts:20-24` suggests yes, which means the trust surface includes "admin can re-point an active adapter at an arbitrary contract."
8. **Decimals handling on losses.** `previewRedeem` returns net USDC after fee — what does it return if `totalAssets() < totalSupply()` (i.e. the vault has lost money)? OZ's default rounds in the vault's favor; whether the exit fee is applied to the loss-adjusted or principal value affects user UX in a drawdown.

---

## 12. References

- ABI: [`packages/cli/src/lib/abi.ts`](../../packages/cli/src/lib/abi.ts)
- Addresses: [`packages/cli/src/lib/addresses.ts`](../../packages/cli/src/lib/addresses.ts)
- Basket constants: [`packages/cli/src/lib/basket/constants.ts`](../../packages/cli/src/lib/basket/constants.ts)
- Storage slot derivation: [`packages/cli/src/lib/storage-slots.ts`](../../packages/cli/src/lib/storage-slots.ts)
- Read-command schemas (with live `get-vault` snapshot): [`plugins/robotmoney-cli/skills/robotmoney-cli/references/read.md`](../../plugins/robotmoney-cli/skills/robotmoney-cli/references/read.md)
- Skill behavioral notes: [`plugins/robotmoney-cli/skills/robotmoney-cli/SKILL.md`](../../plugins/robotmoney-cli/skills/robotmoney-cli/SKILL.md)
- Public roadmap: https://www.robotmoney.net/changelog
- Vault on BaseScan: https://basescan.org/address/0x4f835c9f54bcf17daf9040f60cb72951ccbb49dd
