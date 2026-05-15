# Deploy
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/e1269e8b8cad4814263c616cac976e46cf68e4a1/contracts/script/Deploy.s.sol)

**Inherits:**
Script

**Title:**
Deploy

Foundry deploy script for the Robot Money gateway stack.
Deploys RobotMoneyVault + PassthroughAdapter as the primary vault,
wires a RobotMoneyGateway to the vault, grants AGENT_ROLE to a
distinct EOA via `authorizeAgent`, asserts role-separation, and
writes a deployment JSON.
MockVault is NOT deployed by this script; it is only used by
gateway deposit-routing unit tests directly. See issue #277.
The vault deploys with exitFeeBps=0 and a single PassthroughAdapter
(no external calls) suitable for the smoke-test devnet.

Implements `docs/implementation-plan.md` §5 step 1–2 and
satisfies issue #10. Inputs are env-driven so the same script works
on Anvil, the docker devnet, and (with care) any throwaway L1.
Required env vars:
ADMIN_ADDRESS         — receives DEFAULT_ADMIN_ROLE + ADMIN_ROLE
PAUSER_ADDRESS        — receives PAUSER_ROLE (must differ from ADMIN)
AGENT_ADDRESS         — receives AGENT_ROLE  (must differ from both)
SHARE_RECEIVER_ADDRESS — recipient of minted rmUSDC shares
USDC_ADDRESS          — address of the USDC token to bind the
gateway to. The smoke-test devnet seeds the
canonical Base USDC into genesis alloc and
exports this address (see issue #255 and
`Fixture::fund_usdc` in the smoke-test
crate). Forge unit tests deploy a
`TestERC20` helper and pass its address
via `runInProcessWithUsdc`.
Optional env vars (with safe defaults):
AGENT_VALID_UNTIL      — uint64, default = block.timestamp + 30 days
AGENT_MAX_PER_PAYMENT  — uint256, default = 10_000 * 1e6 (USDC, 6dp)
AGENT_MAX_PER_WINDOW   — uint256, default = 100_000 * 1e6
DEPLOYMENT_OUT         — output JSON path,
default = "deployments/<chain_id>.json"


## Constants
### CANONICAL_BASE_USDC
Canonical Base mainnet USDC (FiatTokenProxy). The smoke-test
devnet seeds this address with real proxy storage + the
FiatTokenV2_2 implementation in genesis alloc.


```solidity
address public constant CANONICAL_BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```


### DEFAULT_MAX_PER_PAYMENT
Default per-payment cap if `AGENT_MAX_PER_PAYMENT` is unset.


```solidity
uint256 public constant DEFAULT_MAX_PER_PAYMENT = 10_000 * 1e6
```


### DEFAULT_MAX_PER_WINDOW
Default per-window cap if `AGENT_MAX_PER_WINDOW` is unset.


```solidity
uint256 public constant DEFAULT_MAX_PER_WINDOW = 100_000 * 1e6
```


### DEFAULT_VALID_UNTIL_OFFSET
Default policy lifetime (30 days).


```solidity
uint64 public constant DEFAULT_VALID_UNTIL_OFFSET = 30 days
```


## Functions
### run

Forge broadcast entrypoint. Reads env vars, deploys all contracts, and writes a JSON file.


```solidity
function run() external returns (Deployed memory d);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`d`|`Deployed`|Struct containing all deployed contract addresses and key parameters.|


### runInProcess

In-process variant for forge tests. Caller sets up `vm.prank`
or test-account context. No JSON is written.


```solidity
function runInProcess() external returns (Deployed memory d);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`d`|`Deployed`|Struct containing all deployed contract addresses and key parameters.|


### runInProcessWith

Direct-parameter variant for forge tests. Skips env-var
resolution so a noisy host environment (or another test's
residual `vm.setEnv`) cannot pollute the inputs. The caller
must supply a deployed USDC token (typically a `TestERC20`).


```solidity
function runInProcessWith(
    address admin_,
    address pauser_,
    address agent_,
    address shareReceiver_,
    address usdc_
) external returns (Deployed memory d);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin_`|`address`|        Address to receive `DEFAULT_ADMIN_ROLE` and `ADMIN_ROLE`.|
|`pauser_`|`address`|       Address to receive `PAUSER_ROLE`.|
|`agent_`|`address`|        Address to receive `AGENT_ROLE`.|
|`shareReceiver_`|`address`|Address that will receive minted vault shares.|
|`usdc_`|`address`|         Address of the USDC token to bind to the gateway.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`d`|`Deployed`|Struct containing all deployed contract addresses and key parameters.|


### _readEnvParams


```solidity
function _readEnvParams() internal view returns (Params memory p);
```

### _doDeploy


```solidity
function _doDeploy(Params memory p) internal returns (Deployed memory d);
```

### _envOrDefault


```solidity
function _envOrDefault(string memory key, uint256 fallbackValue)
    internal
    view
    returns (uint256);
```

### _writeDeploymentJson


```solidity
function _writeDeploymentJson(Deployed memory d) internal;
```

## Structs
### Deployed
Result struct returned to in-process callers (e.g. forge tests).

`usdc` is the *address* of the externally-supplied USDC token
bound to the gateway. On the smoke-test devnet this is the
canonical Base USDC proxy seeded into genesis alloc; in forge
unit tests it is a `TestERC20` deployed by the caller.
`vault` is the deployed RobotMoneyVault (smoke-test devnet and
integration tests). For gateway unit tests that still need MockVault,
use the separate `MockVault` import directly.
`adapter` is the PassthroughAdapter wired into vault at deploy time.


```solidity
struct Deployed {
    address usdc;
    RobotMoneyVault vault;
    PassthroughAdapter adapter;
    RobotMoneyGateway gateway;
    address admin;
    address pauser;
    address agent;
    address shareReceiver;
    bytes32 gatewayRuntimeHash;
}
```

### Params

```solidity
struct Params {
    address admin;
    address pauser;
    address agent;
    address shareReceiver;
    uint64 validUntil;
    uint256 maxPerPayment;
    uint256 maxPerWindow;
    /// @dev Address of the USDC token to bind the gateway to. Must be
    ///      non-zero and have code deployed. The smoke-test devnet sets
    ///      this to the canonical Base USDC ([`CANONICAL_BASE_USDC`]);
    ///      forge unit tests deploy a `TestERC20` helper.
    address usdcAddress;
}
```

