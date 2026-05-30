# GuardHarness
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/d2f11e55183cacf89c19558c72523157397a4856/contracts/test/AdapterDelegatecallGuard.t.sol)

Library-consumer harness so we can test `requireNoDelegatecall`
with `vm.expectRevert` against the library's custom error.


## Functions
### requireNoDelegatecall


```solidity
function requireNoDelegatecall(address adapter_) external view;
```

### containsDelegatecall


```solidity
function containsDelegatecall(bytes memory code) external pure returns (bool);
```

