# DemoVaultBatchDeployer
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/b2783a9fccc37987f2403e8b51396991d9825f59/contracts/script/DeployDemoExtraVaults.s.sol)

One-shot batch deployer for all CREATE-heavy demo seed contracts.
Its constructor performs every demo CREATE in a single broadcaster
transaction:
- 3 × `RobotMoneyVault` (extra vault1, extra vault2, RWA placeholder)
- 2 × `PassthroughAdapter` (one per extra vault)
- 1 × `AgentTokenVault` (MVP six-token basket)
- 1 × `AgentBasketStubDeployer` (which itself sub-CREATEs the 12
basket stand-ins: 6 × `DemoAgentToken` + 6 × `DemoUsdcPool`)
All vaults are constructed with `admin = adminAddr` so the
broadcaster (which the script passes in as `adminAddr`) retains
ADMIN_ROLE — subsequent admin calls like `vault.addAdapter`,
`setAdapterAllowed`, `addAsset`, registry ops still come from the
script's broadcast key and work unchanged. Demo-only; not deployed
on mainnet.


## Constants
### vault1

```solidity
RobotMoneyVault public immutable vault1
```


### vault2

```solidity
RobotMoneyVault public immutable vault2
```


### rwaVault

```solidity
RobotMoneyVault public immutable rwaVault
```


### adapter1

```solidity
PassthroughAdapter public immutable adapter1
```


### adapter2

```solidity
PassthroughAdapter public immutable adapter2
```


### agentVault

```solidity
AgentTokenVault public immutable agentVault
```


### basketStubs

```solidity
AgentBasketStubDeployer public immutable basketStubs
```


## Functions
### constructor


```solidity
constructor(
    address usdc,
    address adminAddr,
    address swapRouter,
    uint256 tvlCap,
    uint256 perDepositCap,
    string[6] memory agentSymbols
) ;
```

