# MockVaultForRouter
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/e1269e8b8cad4814263c616cac976e46cf68e4a1/contracts/test/DeployPortfolioRouter.t.sol)

Minimal ERC-4626-shaped mock vault for router weight tests.
Only implements the subset required by PortfolioRouter.setWeights
(which calls registry.getVault to validate, not the vault itself).


