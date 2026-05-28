# DemoAgentToken
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/81cc01fb38d05b8378cb638b175e1ee437aad146/contracts/script/DeployDemoExtraVaults.s.sol)

**Inherits:**
ERC20

Demo-only stand-in ERC20 for the AgentTokenVault shortlist. The
devnet has no real agent-token liquidity; this fills the basket so
`AgentTokenVault.shortlist()` returns the six MVP tokens for the
dapp. Never deployed on mainnet (DeployDemoExtraVaults is demo-only).


## Functions
### constructor


```solidity
constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_);
```

