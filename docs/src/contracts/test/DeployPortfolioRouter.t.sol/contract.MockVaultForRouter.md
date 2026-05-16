# MockVaultForRouter
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/8d3063d04db80ac17c3412499340ecc0e610e041/contracts/test/DeployPortfolioRouter.t.sol)

Minimal ERC-4626-shaped mock vault for router weight tests.
Only implements the subset required by PortfolioRouter.setWeights
(which calls registry.getVault to validate, not the vault itself).


