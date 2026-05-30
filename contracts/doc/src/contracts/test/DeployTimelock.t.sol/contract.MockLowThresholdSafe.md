# MockLowThresholdSafe
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/d2f11e55183cacf89c19558c72523157397a4856/contracts/test/DeployTimelock.t.sol)

Minimal stub that mimics a 1-of-N Safe — `getThreshold()` returns 1.
Used to prove DeployTimelock rejects low-threshold Safes.


## Functions
### getThreshold


```solidity
function getThreshold() external pure returns (uint256);
```

