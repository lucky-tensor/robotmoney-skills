# DeployTest
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/e1269e8b8cad4814263c616cac976e46cf68e4a1/contracts/test/Deploy.t.sol)

**Inherits:**
Test

Exercises the deploy script in-process and asserts the post-deploy
invariants the operator and downstream tooling rely on (issue #10).
The script now deploys RobotMoneyVault + PassthroughAdapter (issue #277)
instead of MockVault. MockVault is retained only for gateway unit tests.
The script always binds the gateway to an externally-supplied USDC
token; this test deploys a `TestERC20` helper and passes its address
in. The smoke-test devnet does the same with the canonical Base USDC
proxy seeded into genesis alloc (issue #255).


## State Variables
### script

```solidity
Deploy internal script
```


### usdc

```solidity
TestERC20 internal usdc
```


### admin

```solidity
address internal admin = makeAddr("admin")
```


### pauser

```solidity
address internal pauser = makeAddr("pauser")
```


### agent

```solidity
address internal agent = makeAddr("agent")
```


### shareReceiver

```solidity
address internal shareReceiver = makeAddr("shareReceiver")
```


## Functions
### setUp


```solidity
function setUp() public;
```

### _run


```solidity
function _run() internal returns (Deploy.Deployed memory);
```

### test_deploy_wiresUsdcVaultAndAdminPauserRoles


```solidity
function test_deploy_wiresUsdcVaultAndAdminPauserRoles() public;
```

### test_deploy_authorizesAgentWithSanePolicy


```solidity
function test_deploy_authorizesAgentWithSanePolicy() public;
```

### test_deploy_doesNotMintToAgent


```solidity
function test_deploy_doesNotMintToAgent() public;
```

### test_deploy_revertsWhenUsdcAddressZero


```solidity
function test_deploy_revertsWhenUsdcAddressZero() public;
```

### test_deploy_revertsWhenUsdcAddressHasNoCode


```solidity
function test_deploy_revertsWhenUsdcAddressHasNoCode() public;
```

### test_deploy_grantingAgentRoleToAdminReverts


```solidity
function test_deploy_grantingAgentRoleToAdminReverts() public;
```

### test_deploy_grantingAgentRoleToPauserReverts


```solidity
function test_deploy_grantingAgentRoleToPauserReverts() public;
```

### test_deploy_revertsWhenAdminEqualsPauser


```solidity
function test_deploy_revertsWhenAdminEqualsPauser() public;
```

### test_deploy_revertsWhenAdminEqualsAgent


```solidity
function test_deploy_revertsWhenAdminEqualsAgent() public;
```

### test_deploy_revertsWhenPauserEqualsAgent


```solidity
function test_deploy_revertsWhenPauserEqualsAgent() public;
```

### test_deploy_envDriven_runInProcessSucceeds


```solidity
function test_deploy_envDriven_runInProcessSucceeds() public;
```

