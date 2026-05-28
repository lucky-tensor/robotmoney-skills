# DemoExtraVaultsBatchDeployer
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/81cc01fb38d05b8378cb638b175e1ee437aad146/contracts/script/DeployDemoExtraVaults.s.sol)

Batch deployer #1 — the two extra demo RobotMoneyVaults and their
PassthroughAdapters. Performs four sub-CREATEs (vault1, vault2,
adapter1, adapter2) inside a single broadcaster CREATE. Split from
the RWA + AgentTokenVault batch so the combined initcode stays
under the EIP-3860 max-initcode limit (49152 bytes) — geth enforces
this on the smoke-test devnet even though forge tests do not.
All vaults are constructed with admin = adminAddr (the script
broadcaster), so subsequent admin calls (addAdapter,
setAdapterAllowed, registry ops) still come from the broadcast key
and work unchanged. Demo-only.


## Constants
### vault1

```solidity
RobotMoneyVault public immutable vault1
```


### vault2

```solidity
RobotMoneyVault public immutable vault2
```


### adapter1

```solidity
PassthroughAdapter public immutable adapter1
```


### adapter2

```solidity
PassthroughAdapter public immutable adapter2
```


## Functions
### constructor


```solidity
constructor(address usdc, address adminAddr, uint256 tvlCap, uint256 perDepositCap) ;
```

