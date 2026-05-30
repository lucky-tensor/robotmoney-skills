# IRouterDefaultWeights
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/d2f11e55183cacf89c19558c72523157397a4856/contracts/VaultRegistry.sol)

Minimal view the registry needs from `PortfolioRouter` to keep the
default weight vector's length consistent with router eligibility.
Declared as an interface (not an import) to avoid a circular
compile-time dependency between the two contracts.


## Functions
### defaultWeightsLength

Number of legs in the router's default weight vector.


```solidity
function defaultWeightsLength() external view returns (uint256);
```

