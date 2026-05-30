# ISafeMinimal
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/d2f11e55183cacf89c19558c72523157397a4856/contracts/script/DeployTimelock.s.sol)

Minimal Safe interface — only `getThreshold()` is required for the
deploy-time guard that rejects EOA or low-threshold Safe addresses.


## Functions
### getThreshold


```solidity
function getThreshold() external view returns (uint256);
```

