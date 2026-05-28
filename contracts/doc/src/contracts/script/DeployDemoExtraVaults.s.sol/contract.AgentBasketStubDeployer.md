# AgentBasketStubDeployer
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/81cc01fb38d05b8378cb638b175e1ee437aad146/contracts/script/DeployDemoExtraVaults.s.sol)

One-shot batch deployer for the AgentTokenVault devnet basket
stand-ins. Its constructor performs all 12 sub-`CREATE`s (six
`DemoAgentToken` + six `DemoUsdcPool`) in a single broadcaster
transaction. The script then makes one `vault.addAsset(...)` call
per token. This collapses the per-symbol broadcast loop from 18
transactions (6 × token + pool + addAsset) down to 7, keeping the
smoke-test chain-boot inside the dapp-e2e `globalSetup` budget on
GH-hosted runners. Demo-only; never deployed on mainnet.


## State Variables
### tokens

```solidity
DemoAgentToken[6] public tokens
```


### pools

```solidity
DemoUsdcPool[6] public pools
```


## Functions
### constructor


```solidity
constructor(string[6] memory symbols, address usdc) ;
```

