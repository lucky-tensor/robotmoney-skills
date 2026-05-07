# Robot Money — Open Questions

Unresolved questions derived from reading the three source documents in `docs/papers/`:

- `Robot-Money-Whitepaper-v01.md` (Protocol Specification v0.1, February 2026)
- `robot_money_plan_v4.md` (Gen Ventures × ZHC plan)
- `robot_money_prd.md` (PRD MVP v1.0, March 2026)

The docs were authored at different moments with different scopes and were not reconciled before being collected here. This document captures (1) cross-document contradictions that require a product decision, (2) open questions the source docs explicitly flag, and (3) gaps that none of the docs address.

For each item, two streams of additional context are surfaced inline where applicable:

- **Implementation evidence** — what the deployed contract (`contracts/RobotMoneyVault.sol`, `0x4f835c9f54bcf17daf9040f60cb72951ccbb49dd` on Base mainnet), the adapters (`contracts/adapters/{Aave,Compound,Morpho}*.sol`), the gateway (`contracts/gateway/RobotMoneyGateway.sol`), or the repo's own product spec (`docs/prd.md`) reveal. The code and repo PRD were reverse-engineered from a deployed demo contract — they show what was actually built, which is not necessarily what was intended, agreed, or final.
- **Product owner input** — direction conveyed verbally by the product owner (Lex Sokolin, 2026-05-06). These are stated intentions, not yet written into specs the repo can verify, but they reflect the team's current thinking about direction.

Both streams are inputs to the decision, not the decision itself. Where a stream is silent on a question, that silence is noted but does not constitute an answer.

---

## 1. Cross-document contradictions

These are points where two or more documents make incompatible claims. Each needs a decision before any of the docs can be published externally as a coherent set.

### 1.1 One token or two?

- **Whitepaper**: single `$ROBOTMONEY`, fixed 1B supply via Clanker v4, LP locked until 2100. Value accrues only through buyback-and-burn from prop-wallet realized gains. Explicitly: "no inflationary yield … staking $ROBOTMONEY does not earn more $ROBOTMONEY."
- **Plan v4**: two-token path. `$RM v1` (Clanker community token) → `$RM v2` (custom contract with **staking and fee distribution**), v1→v2 exchange with early-mover bonus.
- **PRD**: single `$RM`, governance only. No v1/v2.

**Question:** Is there a v2 protocol token with staking and fee distribution, or is the burn-only Clanker token the permanent design?

**Why it matters:** Plan v4's "fee distribution to stakers" directly contradicts the whitepaper's burn-only accrual. The two cannot both be true. This also determines whether early `$RM` buyers face dilution/migration risk.

**Implementation evidence:** No token contract is in this repo. The repo PRD §5.3 refers to `$ROBOTMONEY` as a single fixed-supply governance token with no staking and no fee distribution to holders. The repo's product narrative is consistent with the whitepaper's single-token model and inconsistent with plan v4's migration path. The absence of a token contract means the repo cannot rule out a future v2 — it simply doesn't reflect one.

**Product owner input:** The token is "a voting heartbeat for AIs to contribute to allocation voting and try to bribe in their own assets to vaults." Framed as governance + designed-in bribery flow, not a yield-bearing instrument. Described as a "separate build attempt … described in specs" not in this repo. Consistent with single-token, governance-only — no v2 mentioned.

### 1.2 Vault: three-bucket from launch, or stables-first?

- **Whitepaper**: 33/33/33 stables / agent-token trading / revenue tokens **from day one**. Monthly bucket-weight rebalance.
- **Plan v4**: stables-only genesis vault in Phase 1. Robot-coin baskets in Phase 3 (Weeks 8–16). Protocol/DeFi tokens Phase 4.
- **PRD**: vault is referred to as future ("before the vault ships"); CFO Feed exists partly to fill the gap.

**Question:** What is in the vault on day one — three buckets or a single-strategy stables vault?

**Why it matters:** Affects launch-week TVL targets, smart-contract scope, audit surface, and the GTM narrative ("managed three-bucket exposure" vs. "stable yield, expanding").

**Implementation evidence:** `RobotMoneyVault.sol` is an ERC-4626 vault whose asset is USDC. It holds a flat array of strategy adapters — no bucket A/B/C structure. The three deployed adapter types (Aave V3, Compound V3, Morpho) are all USDC stable-yield venues. The repo PRD §5.2 says: *"Bucket-B and bucket-C tokens land directly in the depositor's wallet at deposit time. The treasury custodies stable-yield positions only."* The vault as built only does Bucket A. The code alone cannot distinguish whether that's a permanent stables-only design with B/C as an off-treasury delivery layer, a phased rollout with B/C still to come, or an abandonment of the whitepaper's three-bucket-in-vault model. Repo PRD §5.2 supports the first reading; plan v4 is consistent with the second; the whitepaper is incompatible with both.

**Product owner input:** The intended architecture is multi-vault, not multi-bucket-in-one-vault: *"multi-vault of n vaults, and then receipt tokens for vaults, and then that maybe or maybe not wrapped into a vault. Perhaps people can opt into different mixes of exposure."* Specific vaults named: stables ("sort of done" — matches the deployed contract; Giza and Zyfai mentioned as additional strategy candidates), a protocol vault (ETH/BTC/SOL), an agent-token vault ("not done", with the voting/bribery use case attached), and a possible RWA vault (SP500 via a Hyperliquid position; commodities). Veda was considered as an off-the-shelf provider; the team chose to build in-house ("opened the can of worms"). This reframes the question: it is not three-bucket-vs-stables-first but a sequence of separate vault contracts, with an optional meta-vault wrapper for blended exposure.

### 1.3 Shortlist curation: top-down or bottom-up?

- **Whitepaper**: the protocol's agent runs the quant screen and **publishes** the shortlist of 10–15 tokens. Holders only rank.
- **PRD**: any Analyst-tier (100M `$RM`) agent **proposes** tokens. 48h Approve/Reject inclusion vote at 3% quorum. 15-token cap with displacement rules.

**Question:** Who decides what is on the shortlist — the protocol agent (curated) or `$RM` holders via inclusion proposals (community-driven)?

**Why it matters:** Different governance topologies. Curated is faster and lower-overhead; proposal-driven creates `$RM` demand from projects wanting inclusion. The PRD's whole eligibility/tier/activity machinery only exists if the answer is proposal-driven.

**Implementation evidence:** No governance contract is in the repo. The vault uses OpenZeppelin `AccessControl` with three roles: `ADMIN_ROLE`, `EMERGENCY_ROLE`, `KEEPER_ROLE`. Adapters are added/removed by ADMIN_ROLE. There is no on-chain proposal, vote, snapshot, or quorum logic. Repo PRD §7 says: *"The path from a vote to an admin action is bounded by the multisig operating within published constraints."* Whatever shortlist curation happens, it currently happens off-chain and is executed by a multisig — silence on the curated-vs-proposal-driven question, not an answer to it.

**Product owner input:** The bribery flow ("AIs … try to bribe in their own assets to vaults") is explicitly designed-in, which reads as bottom-up — agents pay/lobby `$RM` to push their tokens into the agent-token vault. Mechanics deferred to "specs". Consistent with the source PRD's proposal-driven model; inconsistent with the whitepaper's purely-curated model.

### 1.4 Voting mechanic for weekly allocation

- **Whitepaper**: ranked-choice voting over the shortlist.
- **PRD**: basis-point allocation (each agent distributes 0–10,000 bps across up to 15 tokens), weighted by `$RM` balance.

**Question:** Ranked choice or weighted bps allocation?

**Why it matters:** They produce different outcomes from the same inputs and require different UI, tally logic, and gaming-resistance analysis.

**Implementation evidence:** No on-chain voting. Adapter target weights inside the vault are computed dynamically as `targetBps = MAX_BPS / activeAdapterCount` (`_targetBpsFor()`), with per-adapter `capBps` ceilings. No vote inputs feed into this calculation. The voting-mechanism question has no implementation footprint at all yet; readers cannot infer a preference from absence.

**Product owner input:** Mechanics not specified beyond "voting heartbeat" framing and the bribery flow. Treated as part of the separate token-side build described in specs, not a near-term vault concern.

### 1.5 Tier system: yes or no?

- **PRD**: four tiers (Observer / Participant 10M / Analyst 100M / Strategist 500M) with 14-day activity gate for Analyst+ governance actions.
- **Whitepaper & Plan v4**: no tiers. Anyone with `$RM` can vote, linear weight.

**Question:** Are governance rights gated by both balance tier and recent activity, or only by balance?

**Why it matters:** The activity gate is the PRD's main sybil defense. Removing it weakens governance; keeping it requires the CFO Feed as a prerequisite product.

**Implementation evidence:** The gateway implements per-agent policies via `authorizeAgent` (`maxPerPayment`, `maxPerWindow`, `validUntil`, `shareReceiver`) — operator-set, not derived from `$RM` balance. There is no Observer/Participant/Analyst/Strategist mapping in code. The repo's access control is operator-administered per-agent rather than balance-tier-gated, which is a different axis from the source PRD's tiers (which gate posting/voting/proposal rights). The two could coexist; the source PRD's tier system is not contradicted by the implementation, just not built.

### 1.6 Vault structure: bucketed or flat?

- **Whitepaper**: Bucket A/B/C is structurally central (risk floor, alpha, middle ground). Monthly votes shift bucket *weights*.
- **PRD**: flat list of up to 15 tokens with bps weights. No bucket vocabulary, no bucket-weight vote.
- **Plan v4**: "baskets" — closer to buckets, undefined.

**Question:** Is the vault organized as three risk buckets with intra-bucket selection, or as a flat token list with direct weights?

**Why it matters:** The whitepaper's monthly bucket rebalance vote has no surface in the PRD's governance flows. If buckets are real, the PRD is missing a workflow.

**Implementation evidence:** The vault data model is flat: `AdapterInfo[] public adapters`. No bucket struct. Drift reporting (`getAdapterDrift`) is per-adapter. There is no monthly bucket-weight reweighting surface. As built, "buckets" exist only as a product narrative, not as a contract concept.

**Product owner input:** Neither bucketed nor flat — the model is **multi-vault with receipt tokens, optionally wrapped into a meta-vault** (see §1.2). Each asset class is its own vault; "different mixes of exposure" are produced by combining receipts (or by depositing into a wrapper that holds them). This is a third architecture not described in any of the three source papers, and the closest existing reference is Veda.

### 1.7 Sequencing: what ships first?

- **Whitepaper**: vault contract Week 1–2, token Week 3, first deposits Weeks 4–8. Vault and token roughly simultaneous.
- **Plan v4**: vault + token + agent persona simultaneous in Phase 1 (Weeks 1–2).
- **PRD**: `$RM` is **already live and trading**; vault is **not yet shipped**; CFO Feed is the stopgap.

**Question:** Was the vault live at token launch, will it be, or has the plan now changed to "token first, CFO Feed second, vault later"?

**Why it matters:** The whole strategic story differs. If the vault is not at launch, the whitepaper's day-one fee economics and prop-wallet seeding from launch fees are not yet operative, and `$RM` is purely speculative until the vault ships.

**Implementation evidence:** The vault, adapters, and gateway are deployed (`README.md` cites a BaseScan address for the vault). No `$ROBOTMONEY` token contract, no governance contract, no CFO Feed code is in the repo. As of now, the *vault* shipped first — contradicting the source PRD's premise (which assumes a token-without-vault state) and consistent with the whitepaper's launch sequence. The source PRD's CFO-Feed-as-stopgap rationale presumes a state that has not occurred.

**Product owner input:** Confirms vault-first, with stables vault "sort of done" and the rest staged behind it. Token side is described as a separate build in specs. The current Base deployment is treated as a POC ("this is just POC"); the production deployment target is undecided but explicitly *not* Base — see new question §3.11 below.

### 1.8 Customer wedge

- **Whitepaper**: agents with **idle USDC** seeking diversified managed exposure.
- **Plan v4**: agents **over-concentrated in their own token** seeking to de-risk into stables.
- **PRD**: agents seeking **analytical credibility and governance influence** (CFO Feed).

**Question:** Which is the primary go-to-market wedge?

**Why it matters:** Each wedge implies different onboarding flows. The plan-v4 framing also implicitly requires a swap path (own-token → USDC) that the whitepaper assumes has already happened.

**Implementation evidence:** The Rust client (`clients/rust-payment-client/`), the gateway's per-agent caps, the windowed limits, idempotent payment IDs, and encrypted-keystore signer — all of it is engineered for autonomous-agent USDC deposits. `docs/architecture.md` §1 names the access-layer goal explicitly: agents depositing USDC into the vault under bounded policy. The infrastructure investment to date is concentrated on the whitepaper's wedge. It does not preclude the others — there is no swap-into-USDC primitive (plan v4) and no CFO Feed (source PRD), but neither is ruled out.

**Product owner input:** Implies a wedge broader than any single source paper: agent-economy treasuries on chains with real payment activity. Polygon is mentioned for its payment-activity user base; mainnet for "real" use cases. The agent-token vault carries the bribery/voting use case (governance demand for `$RM`); the RWA vault carries a "story telling" use case (SP500/commodities exposure for narrative). The customer is still agents, but the product surface is broader than just "park idle USDC."

---

## 2. Questions the source docs themselves flag

These are explicitly listed as open in the originals. Re-stated here for tracking.

### From Whitepaper §11

- **Legal entity structure.** Vault accepts deposits and charges a management fee; in most jurisdictions this is fund management. Likely needs offshore foundation (Cayman, BVI) or DAO legal wrapper (Wyoming, Marshall Islands). Counsel review pre-launch. *Implementation evidence: no on-chain reflection.*
- **Performance fee.** Whether to add a 20%-of-gains-above-hurdle fee in addition to the 2% management fee. Deferred to Phase 4 pending track record. *Implementation evidence: not implemented. The vault charges only `exitFeeBps` (capped at 1% by `MAX_EXIT_FEE_BPS`). There is no management-fee accrual and no performance fee in the contract. The whitepaper's 2% management fee and the repo PRD §5.4's three-fee structure are not yet reflected in code.*
- **Deposit caps.** Whether to cap total deposits during bootstrap to limit smart-contract risk exposure. Whitepaper recommends $500K cap in Phase 2, lifted after 60 days incident-free. *Implementation evidence: both global (`tvlCap`) and per-deposit (`perDepositCap`) caps are present and admin-settable; the gateway adds `maxPerWindow` and `maxPerPayment` per agent. The whitepaper's recommendation is straightforwardly implementable with the existing setters.*
- **Multi-chain expansion.** Whether to deploy cross-chain (CCIP, LayerZero) if agent activity migrates from Base. Deferred to Phase 5. *Implementation evidence: Base only. Adapter addresses are Base-mainnet pinned. No CCIP, no LayerZero. A second chain would require new deployments.* *Product owner input: explicitly reverses the whitepaper's Base-default. "We dont want to stay on base or with the base token, this is just POC." Polygon mentioned for payment activity and potential clients; Ethereum mainnet for "more real" deployments. Peaq was considered for omnichain agent wallets and IDs but the tech is "still half baked." See §3.11 for the open chain-selection question.*
- **Agent identity verification.** Whether the vault should verify depositors are agents and not humans. Current answer: no — vault is permissionless. *Implementation evidence: split. The vault itself is permissionless via standard ERC-4626 `deposit`. The gateway only accepts deposits from agent addresses an operator has explicitly authorized via `authorizeAgent`. Both readings can be true depending on the path used.*

### From Plan v4 "Immediate Decisions (Pre-Launch)"

- Genesis vault infrastructure: Compass Labs API vs. direct Aave/Sky vs. custom build. *Implementation evidence: direct integrations (custom adapters) for Aave V3, Compound V3, Morpho. No Compass Labs API in code.*
- Stablecoin selection for the genesis vault: USDC vs. DAI vs. USDE. *Implementation evidence: USDC is the vault's hardcoded asset.*
- Agent persona: identity, hosting, posting infrastructure, and ongoing cost. *Implementation evidence: not in this repo.*
- Tokenomics: supply, fee structure, initial allocation, v1/v2 exchange terms. *Implementation evidence: token not yet deployed.*
- Clanker terms: exact fee structure, factored into v2 exchange economics. *Implementation evidence: not yet relevant.*
- Audit budget and timeline for `$RM v2` (Phase 2–3 dependency). *Implementation evidence: see §1.1 — no v2 reflected in code.*

---

## 3. Gaps — questions none of the docs answer

Topics that are load-bearing for the protocol but not addressed in any source document.

### 3.1 Quant filter operationalization

The thresholds are defined ($10M mcap, 90 days, $100K volume, 500 holders) but not the *measurement methodology*: which oracle/aggregator, what averaging window, how disputes are resolved. The PRD mentions "CoinGecko + on-chain" with "consensus required if sources disagree" but does not specify rules.

*Implementation evidence: off-chain. Not in code.*

### 3.2 Bucket B trading: who is the trader?

The whitepaper says "the agent trades agent-economy tokens using on-chain signals (volume, holder distribution, treasury health, developer activity)" but no doc specifies the trading strategy, position-sizing rules, stop-loss enforcement, or how losses are reported in NAV in real time. The 10%-of-Bucket-B position cap is mentioned once with no enforcement mechanism described.

*Implementation evidence: not in vault. If repo PRD §5.2's framing holds, B-token trading does not happen at the treasury layer at all. Position sizing, stop losses, and intra-trade NAV impact would live in whatever deposit-routing code delivers B/C tokens to the depositor — that code is not in this repo.*

### 3.3 Prop wallet seeding and accounting

The whitepaper says the prop wallet is "seeded from Clanker launch fees" but does not quantify expected initial capital, nor specify how the prop wallet's PnL accounting handles unrealized gains, mark-to-market reporting, or tax-lot identification for buyback triggers.

*Implementation evidence: no prop wallet exists yet. With no token deployed, there is no buyback to fund and no prop wallet operating. The whitepaper's flywheel is forward-looking, not active.*

### 3.4 Multisig composition and trust

The PRD's MVP relies on a 2-of-3 multisig to relay Snapshot results to `vault.rebalance()`. No doc names signers, defines challenge-window dispute resolution, or specifies what happens if signers disagree with the published tally.

*Implementation evidence: not specified in code. AccessControl admits role grants but says nothing about the multisig signer set or threshold. That is a deployment-time configuration, not a contract property.*

### 3.5 Vault upgrade path

The whitepaper says "no upgradeability — immutable contract." But Plan v4 and the PRD describe progressive expansion (new buckets, new strategies, Chainlink Automation, on-chain governance contract). How is "immutable vault" reconciled with "progressive expansion"? Is each phase a new vault deployment with a migration path?

*Implementation evidence: bytecode immutable, parameters mutable, strategy set mutable. Hardcoded floors (`MAX_EXIT_FEE_BPS = 100`, `MAX_REBALANCE_BPS_CEILING = 5000`, `MIN_REBALANCE_INTERVAL_FLOOR = 1 hours`, `MAX_ADAPTERS = 20`) cannot be changed by any role. Configurable params (`tvlCap`, `perDepositCap`, `exitFeeBps`, `feeRecipient`, rebalance throttling) are admin-settable within those floors. Adapters can be added, recapped, removed, force-removed. There is no proxy. There is an irreversible `shutdownVault` flag. So "immutable contract" is true at the bytecode level and false at the strategy-set level. The whitepaper's blanket "immutable" claim and plan v4's "progressive expansion" claim are both partially right; neither matches the code exactly.*

### 3.6 Agent CFO Feed economics

The PRD describes a content product (registration, posting, upvoting, comments) with no fee model. Hosting, RPC, IPFS, and moderation costs are not allocated. Does the CFO Feed run on protocol revenue, separate funding, or fees?

*Implementation evidence: not in this repo.*

### 3.7 Withdrawal mechanics under Bucket B drawdown

Redemptions are at NAV minus 0.25% exit fee. No doc specifies what happens when Bucket B (high-risk active positions) is mid-trade and a depositor wants to exit — forced sale, queued withdrawal, or NAV haircut?

*Implementation evidence: not a vault concern, given §3.2. Vault redemptions pull proportionally from active stable-yield adapters and apply the exit fee. There is no asynchronous queue and no NAV haircut path; withdrawals are synchronous as long as adapter liquidity is available. If B-positions ever land in the treasury (rather than in depositor wallets), the question reopens.*

### 3.8 Inclusion-attack economic bounds

The whitepaper argues the inclusion attack is self-punishing because attackers' `$RM` loses value if their token underperforms. But the magnitude is not modeled: how much `$RM` must an attacker hold to swing weekly allocation, vs. how much vault buy pressure that produces, vs. expected loss on `$RM` from underperformance? Without numbers, "self-punishing" is an assertion, not a proof.

*Implementation evidence: no on-chain attack surface today. With no on-chain governance, the immediate attack surface is the multisig, not a vote tally. Once a token and on-chain voting exist, the question reopens.*

### 3.9 Quorum cliff

If the weekly vote falls just below 5%, the agent default executes; if just above, voted weights execute. No doc addresses smoothing — e.g., a continuous blend between voted and default weights as quorum scales — to avoid governance whiplash week-to-week.

*Implementation evidence: no on-chain quorum logic.*

### 3.10 Failure modes for the protocol agent itself

The protocol agent is a single point of failure: it publishes shortlists, runs the default allocation, executes rebalances, and posts the public narrative. No doc addresses what happens if the agent goes offline, is compromised, hallucinates a bad allocation, or its operator wants to step away. There is no agent-of-last-resort or emergency pause that names a controller.

*Implementation evidence: strong operator override at the contract layer. The vault provides `pause`/`unpause`, `emergencyWithdraw` (yanks all adapter balances and pauses), `emergencyWithdrawAdapter`, `forceRemoveAdapter`, and the irreversible `shutdownVault`. The gateway has its own pause and per-agent revocation. Admin and emergency powers are on roles held by humans/multisig — not on the protocol agent. The keeper role can call `rebalance()` but is bounded by hard ceilings. Whether this surface is sufficient for the agent-driven product narrative is a judgment call; the surface exists.*

### 3.11 Production chain selection

The Base deployment is described by the product owner as a POC, with the production target explicitly elsewhere. Polygon and Ethereum mainnet are named, but no chain is committed. This is a load-bearing decision: it determines the integration set (which DeFi venues, which payment rails, which wallets), the audit scope, and whether the existing adapters need to be re-implemented for new venues.

*Implementation evidence: nothing on chain selection. Existing adapters are Base-pinned.*

*Product owner input: "We dont want to stay on base or with the base token, this is just POC." Polygon for payment activity, mainnet for "more real" use. Peaq considered for omnichain agent wallets/IDs but tech is half-baked.*

### 3.12 Multi-vault wrapping mechanism

The product owner describes "n vaults" with receipt tokens, optionally wrapped into a meta-vault that lets users opt into mixes of exposure. None of the source papers describe this, and the deployed contract is a single ERC-4626. Open: is the wrapper an ERC-4626-of-ERC-4626 (share-of-shares), a router that bundles deposits, an off-chain composite product, or something else? Who sets the mix weights — depositor at deposit time, governance, or the product?

*Implementation evidence: not present.*

*Product owner input: structure described as "multi-vault of n vaults, and then receipt tokens for vaults, and then that maybe or maybe not wrapped into a vault. Perhaps people can opt into different mixes of exposure." Reference point: Veda.*

### 3.13 Build-vs-buy commitment

The product owner introduced existing portfolio-management providers (Veda named as the largest), and the team chose to build in-house anyway — described as "opening the can of worms." This raises an implicit question of scope: how much of the multi-vault platform is in-scope to build, and at what point would integrating Veda (or Giza/Zyfai for the stables vault) be revisited?

*Implementation evidence: in-house implementation underway (the deployed vault is custom, not a Veda integration).*

*Product owner input: build-in-house decision is current; Giza and Zyfai are named as potentially interesting for the stables vault specifically.*

### 3.14 RWA vault feasibility

The product owner mentioned an RWA vault built around a Hyperliquid SP500 perp position, possibly extended to commodities — primarily a "story telling" exposure. None of the source papers describe RWA, and the regulatory and execution mechanics are non-trivial: a perp position is not a spot RWA, and exposing depositors to perp funding/liquidation risk through a "vault" framing has user-protection implications.

*Implementation evidence: not present.*

*Product owner input: RWA vault flagged as a future build for narrative value.*

---

## 4. Patterns across the implementation evidence and product owner input

A few cross-cutting observations worth weighing — signals, not findings.

1. **The intended architecture is multi-vault, not multi-bucket.** The product owner describes n separate vaults with receipt tokens and an optional meta-vault wrapper. None of the three source papers describe this; only the deployed stables vault matches it. Reading §1.2 and §1.6 through this lens turns the question from "buckets vs. flat list" into "which vaults, in what order, and how composed" — closer to a Veda-style platform than to the whitepaper's three-bucket fund.

2. **The Base deployment is explicitly POC, not the production target.** The current vault address on Base is a working demo, not the chain commitment. Any analysis that treats the Base deployment as canonical (audit scope, integration set, regulatory reading) needs to be re-run once a production chain is chosen (§3.11).

3. **There is no on-chain governance and no token.** Every governance-shaped question (§1.3, §1.4, §1.5, §3.8, §3.9) has zero implementation footprint. The product owner places token and governance in a "separate build attempt … described in specs" not in this repo. Decisions in those areas are unconstrained by existing code, and the bribery-driven inclusion mechanism is explicitly designed-in rather than treated as an attack to defend against.

4. **The deployed sequencing inverts the source PRD's premise.** The PRD-paper assumed a token-without-vault state and proposed CFO Feed as a stopgap. The actual deployment is the opposite: vault-without-token. Confirmed by the product owner ("stables vault sort of done"; token described as separate build). Readers re-evaluating the PRD-paper should ask whether its rationale survives the inverted sequencing.

5. **The repo PRD (§5.2 in particular) is the closest source-doc match to the as-built, but it is not the full intended product.** It frames the vault as a stables engine with B/C delivered to depositor wallets — consistent with the deployed contract. The product owner's multi-vault platform vision goes beyond it. Readers may want to treat the repo PRD as a faithful v1 spec for the first vault and the multi-vault wrapping as a v2 design problem the source papers do not yet address.

6. **The implementation has reduced surface in some §3 areas by avoiding the underlying mechanism.** Strong operator override (§3.10), per-agent caps (§3.4 partially), bounded keeper actions, and irreversible shutdown all narrow the attack surface relative to what the source papers describe. This is risk-reduction by *what was not built* (no governance contract, no prop wallet, no token), so the gaps reopen as soon as any of those pieces ship — which the product owner's roadmap does plan.

---

## 5. Suggested resolution order

If decisions need to be sequenced:

1. **§3.11 (production chain selection)** — gates everything else: integration set, adapter rebuild, audit scope, regulatory reading.
2. **§1.1 (one token vs. two)** — affects token economics, legal structure, and token-side build.
3. **§1.2 / §1.6 / §3.12 (multi-vault architecture and wrapping)** — interlocking; resolve as a set. Defines what "Robot Money" actually is as a product.
4. **§3.13 (build vs. buy)** — once the architecture is clear, decide which vaults to build vs. integrate (Veda, Giza, Zyfai).
5. **§1.7 (sequencing)** — fall out of §1.2 and §3.13.
6. **§1.3, §1.4, §1.5 (governance shape)** — interlocking; resolve as a set, after the vault platform shape is settled.
7. **§1.8 (customer wedge)** — narrative; can follow product decisions.
8. **§3.14 (RWA vault feasibility)** — separable, can run in parallel.
9. **§2 items** — defer per the source docs' own phasing.
10. **Remaining §3 gaps** — surface as design tasks once §1 and §2 are settled.
