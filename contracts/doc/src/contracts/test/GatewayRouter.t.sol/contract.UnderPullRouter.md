# UnderPullRouter
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/66300588f0fee2f79bec18799621ba523871f42a/contracts/test/GatewayRouter.t.sol)

Mock router that underpulls USDC during deposit, leaving residual USDC
in the caller (gateway). Used to trigger the router-path USDC custody invariant.


## Constants
### usdc

```solidity
IERC20 public immutable usdc
```


## Functions
### constructor


```solidity
constructor(address usdc_) ;
```

### depositFor


```solidity
function depositFor(address, uint256 amount, uint256[] calldata)
    external
    returns (uint256[] memory sharesPerLeg);
```

