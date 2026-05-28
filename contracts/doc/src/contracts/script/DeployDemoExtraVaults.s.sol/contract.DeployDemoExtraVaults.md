# DeployDemoExtraVaults
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/e0dc44f8c31f4b76f840118b8a9def58d8080e00/contracts/script/DeployDemoExtraVaults.s.sol)

**Inherits:**
Script

**Title:**
DeployDemoExtraVaults

Demo-only deploy script that aligns the devnet vault set with the
four-vault PRD §11 catalog: Stable Yield (deployed by Deploy.s.sol),
Protocol Asset, Agent Token, and an RWA/Thematic placeholder.
Registers all three additions in `VaultRegistry`, seeds the two
basket vaults with devnet stand-in tokens, and resets the router
weight vector to a three-way split across the three Active vaults.
Why this exists: to exercise the full PRD vault catalog end to end
(Portfolio Explorer, /v1/vaults TVL, Router Governance weights) the
demo seed deploys the same vault classes the PRD names — no generic
stand-in clones. `ProtocolAssetVault` and `AgentTokenVault` carry
devnet basket stubs; `RobotMoneyVault` is reused as the RWA
placeholder (Paused, never router-eligible) because PRD §11.4 marks
that vault as Future / not specified — no canonical contract.
Router eligibility: production status per PRD §11.2 and §11.3 marks
the basket vaults as "Prototype — not Router-eligible". The demo
seed *intentionally* overrides this on the devnet registry by
calling `setRouterEligible(true)` on the Protocol and Agent vaults
so the multi-vault Router Governance UI has three Active legs to
display. This is registry state, not a code variant — production
keeps the vaults router-ineligible by simply never running this
script (single-production-codebase, see
`docs/development/single-production-codebase.md`).
Required env vars:
ADMIN_ADDRESS      — receives ADMIN_ROLE on the new vaults and
must already hold ADMIN_ROLE on
VaultRegistry + PortfolioRouter
REGISTRY_ADDRESS   — deployed VaultRegistry
ROUTER_ADDRESS     — deployed PortfolioRouter
PRIMARY_VAULT      — RobotMoneyVault deployed by Deploy.s.sol
(kept in the weight vector with the largest
share)
USDC_ADDRESS       — ERC-20 asset every vault denominates in
WEIGHT_PRIMARY_BPS — bps for PRIMARY_VAULT in the new vector
WEIGHT_EXTRA1_BPS  — bps for ProtocolAssetVault
WEIGHT_EXTRA2_BPS  — bps for AgentTokenVault
(the three must sum to 10 000)
Optional env vars:
SWAP_ROUTER        — Uniswap V3 SwapRouter02 address for the
basket vaults (defaults to Base mainnet)
RWA_VAULT_NAME     — registry name for the RWA/Thematic
placeholder
(default: "Robot Money RWA / Thematic")
DEPLOYMENT_OUT     — output JSON path
(default: "deployments/demo-extra-vaults-<chain_id>.json")


## Constants
### DEMO_AGENT_SWAP_FEE
Default swap fee tier for demo stand-in pools (agent tokens are
illiquid; matches AgentTokenVault's 3% default-slippage stance).


```solidity
uint24 internal constant DEMO_AGENT_SWAP_FEE = 10_000
```


### DEMO_PROTOCOL_SWAP_FEE
Swap fee tier for the protocol-asset basket stubs (mainnet wETH
pools commonly use 0.05%; matches the 1% default-slippage stance
on `ProtocolAssetVault` headroom).


```solidity
uint24 internal constant DEMO_PROTOCOL_SWAP_FEE = 500
```


### DEFAULT_RWA_NAME
Default human-readable name for the RWA/Thematic placeholder
(PRD §11.4). Future / not-specified vault category.


```solidity
string public constant DEFAULT_RWA_NAME = "Robot Money RWA / Thematic"
```


### DEMO_TVL_CAP
TVL cap mirrored from Deploy.s.sol (10M USDC) — demo vaults
carry the same caps as the primary so the harness can fund any
scenario without per-vault tuning.


```solidity
uint256 public constant DEMO_TVL_CAP = 10_000_000 * 1e6
```


### DEMO_PER_DEPOSIT_CAP
Per-deposit cap mirrored from Deploy.s.sol (1M USDC).


```solidity
uint256 public constant DEMO_PER_DEPOSIT_CAP = 1_000_000 * 1e6
```


### DEFAULT_SWAP_ROUTER
Base mainnet Uniswap V3 SwapRouter02 — default basket-vault swap
router when SWAP_ROUTER is unset (mirrors the basket vaults).


```solidity
address internal constant DEFAULT_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481
```


## State Variables
### AGENT_SYMBOLS
Canonical MVP AgentTokenVault shortlist symbols, in deploy order
(docs/adr/ADR-0001-mvp-agent-token-shortlist.md). PEAQ excluded.


```solidity
string[6] internal AGENT_SYMBOLS = ["JUNO", "ROBOTMONEY", "BANKR", "ZYFAI", "GIZA", "DEUS"]
```


### PROTOCOL_SYMBOLS
ProtocolAssetVault basket symbols (PRD §11.2 — wETH, cbBTC, wSOL).


```solidity
string[3] internal PROTOCOL_SYMBOLS = ["wETH", "cbBTC", "wSOL"]
```


## Functions
### run

Forge broadcast entrypoint. Deploys ProtocolAssetVault,
AgentTokenVault, the RWA placeholder; registers all three;
seeds the two basket vaults; resets the router weight vector.


```solidity
function run() external returns (Deployed memory d);
```

### runInProcess

In-process entrypoint for forge tests. Runs the same deploy +
seed body as `run()` but without `vm.startBroadcast`, so the
caller (the test contract) is the broadcaster and must already
hold ADMIN_ROLE on the registry and router. No deployment JSON
is written.


```solidity
function runInProcess(Params memory p) external returns (Deployed memory d);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`p`|`Params`|Fully-formed params (no env reads).|


### _readParams


```solidity
function _readParams() internal view returns (Params memory p);
```

### _doDeploy

Caller must hold ADMIN_ROLE on registry + router via broadcast
key. Splits the body of `run()` so the locals stay below the
stack-too-deep limit.


```solidity
function _doDeploy(Params memory p) internal returns (Deployed memory d);
```

### _seedProtocolAssetVault

Wire the three PRD §11.2 basket symbols into the pre-built
`ProtocolAssetVault` via `addAsset`. Tokens + USDC pool stubs were
already created inside `ProtocolBasketStubDeployer`. The vault's
ADMIN_ROLE is held by p.admin, so addAsset succeeds on the
script broadcast key.


```solidity
function _seedProtocolAssetVault(ProtocolAssetVault vault, ProtocolBasketStubDeployer seeder)
    internal
    returns (address[] memory tokens);
```

### _seedAgentTokenVault

Wire the six MVP shortlist symbols into the pre-built
`AgentTokenVault` via `addAsset`. Same shape as the Protocol
basket seeding above — tokens + USDC pool stubs were already
created inside `AgentBasketStubDeployer`.


```solidity
function _seedAgentTokenVault(AgentTokenVault vault, AgentBasketStubDeployer seeder)
    internal
    returns (address[] memory tokens);
```

### _applyThreeWayWeights

Set both the voted weight vector (used by the AC3 smoke test which
reads `getWeights()`) and the on-chain default (below-quorum
fallback, ADR-0002) to the same three-way split. Bundled into one
helper to keep the `_doDeploy` stack below the solc limit.


```solidity
function _applyThreeWayWeights(
    PortfolioRouter router,
    address primary,
    address protocol,
    address agent,
    Params memory p
) internal;
```

### _setThreeWayWeights


```solidity
function _setThreeWayWeights(
    PortfolioRouter router,
    address primary,
    address protocol,
    address agent,
    Params memory p
) internal;
```

### _setThreeWayDefaultWeights

Populate the router's default (below-quorum fallback) weight vector
with the same three-way split. ADR-0002: this is the vector the
router routes by — and the allocation surface renders — with no
governance activity.


```solidity
function _setThreeWayDefaultWeights(
    PortfolioRouter router,
    address primary,
    address protocol,
    address agent,
    Params memory p
) internal;
```

### _registerIfAbsent

Register `vault` in `registry` if not already present. Returns
true if registration happened, false if already there.


```solidity
function _registerIfAbsent(
    VaultRegistry registry,
    address vault,
    address asset,
    string memory vaultName
) internal returns (bool registered);
```

### _envStringOrDefault


```solidity
function _envStringOrDefault(string memory key, string memory fallback_)
    internal
    view
    returns (string memory);
```

### _envAddressOrDefault


```solidity
function _envAddressOrDefault(string memory key, address fallback_)
    internal
    view
    returns (address);
```

### _logResult


```solidity
function _logResult(Deployed memory d) internal view;
```

### _writeDeploymentJson


```solidity
function _writeDeploymentJson(Deployed memory d) internal;
```

## Structs
### Deployed
Result struct returned to in-process callers (e.g. forge tests).


```solidity
struct Deployed {
    /// @dev `ProtocolAssetVault` (PRD §11.2). Registered Active and made
    ///      router-eligible for the demo (override of the production
    ///      "not Router-eligible" status).
    address protocolVault;
    /// @dev Devnet stand-in ERC20 addresses seeded into ProtocolAssetVault.
    address[] protocolTokens;
    /// @dev `AgentTokenVault` (PRD §11.3). Registered Active and made
    ///      router-eligible for the demo (override of the production
    ///      "not Router-eligible" status).
    address agentTokenVault;
    /// @dev Devnet stand-in ERC20 addresses seeded into AgentTokenVault
    ///      (six MVP shortlist symbols, ADR-0001).
    address[] agentTokens;
    /// @dev RWA/Thematic placeholder (PRD §11.4). Registered non-Active
    ///      (Paused) and never router-eligible; not in the weight vector.
    address rwaVault;
    uint256 weightPrimaryBps;
    uint256 weightProtocolBps;
    uint256 weightAgentBps;
}
```

### Params
Env-derived params bundled to keep `run()` locals below the
Solidity stack limit (16 slots, ~stack-too-deep).


```solidity
struct Params {
    address admin;
    address registry;
    address router;
    address primaryVault;
    address usdc;
    // Uniswap V3 SwapRouter02 for the basket vaults. On devnet no swaps run
    // during seed (only addAsset + register), so a non-functional address
    // is acceptable; defaults to the Base mainnet SwapRouter02.
    address swapRouter;
    uint256 wPrimary;
    uint256 wProtocol;
    uint256 wAgent;
    string rwaName;
}
```

