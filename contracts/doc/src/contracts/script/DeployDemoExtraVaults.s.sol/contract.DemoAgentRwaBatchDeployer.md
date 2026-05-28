# DemoAgentRwaBatchDeployer
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/81cc01fb38d05b8378cb638b175e1ee437aad146/contracts/script/DeployDemoExtraVaults.s.sol)

Batch deployer #2 — the RWA/Thematic placeholder vault plus the
AgentTokenVault. Performs two direct sub-CREATEs (rwaVault,
agentVault) inside a single broadcaster CREATE. Kept separate
from `AgentBasketStubDeployer` so that adding either contract
doesn't push combined initcode over EIP-3860's 49152-byte limit
(geth enforces this on the smoke-test devnet). All vaults
constructed with admin = adminAddr (the script broadcaster).
Demo-only.


## Constants
### rwaVault

```solidity
RobotMoneyVault public immutable rwaVault
```


### agentVault

```solidity
AgentTokenVault public immutable agentVault
```


## Functions
### constructor


```solidity
constructor(
    address usdc,
    address adminAddr,
    address swapRouter,
    uint256 tvlCap,
    uint256 perDepositCap
) ;
```

