# UnderPullRouter
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/4657e0998ea86d624b2c44e64051b74c4f3664c9/contracts/test/GatewayRouter.t.sol)

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

