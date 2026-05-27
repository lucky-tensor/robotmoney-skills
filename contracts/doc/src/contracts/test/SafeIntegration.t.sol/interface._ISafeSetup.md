# _ISafeSetup
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/6ff4c445ad1cd2f918eebf812e95386b19961307/contracts/test/SafeIntegration.t.sol)

Used only to generate the `setup(...)` calldata for SafeProxyFactory.
Not imported from a Safe library to keep the test self-contained.


## Functions
### setup


```solidity
function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address to,
    bytes calldata data,
    address fallbackHandler,
    address paymentToken,
    uint256 payment,
    address payable paymentReceiver
) external;
```

