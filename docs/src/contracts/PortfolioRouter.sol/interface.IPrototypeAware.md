# IPrototypeAware
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/4657e0998ea86d624b2c44e64051b74c4f3664c9/contracts/PortfolioRouter.sol)

Minimal introspection interface used to detect vaults that
self-declare prototype status via `isPrototype()`. Implemented by
`contracts/vaults/BasketVault.sol` and inherited by every
`BasketVault` subclass. Defined here as a local interface so
`PortfolioRouter` has no compile-time dependency on the prototype
vaults themselves — any contract that exposes `isPrototype()
returns (bool)` participates in the production-readiness gate.


## Functions
### isPrototype


```solidity
function isPrototype() external view returns (bool);
```

