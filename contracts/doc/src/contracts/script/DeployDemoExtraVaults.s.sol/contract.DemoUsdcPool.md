# DemoUsdcPool
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/64eee9d202b7e796683417ca7cdefa3349855679/contracts/script/DeployDemoExtraVaults.s.sol)

Minimal Uniswap V3 pool stub exposing only `token0()`/`token1()`,
the two reads `BasketVault.addAsset` uses to verify a pool pairs the
basket token with USDC. Demo-only; no swap/observe liquidity.


## Constants
### token0

```solidity
address public immutable token0
```


### token1

```solidity
address public immutable token1
```


## Functions
### constructor


```solidity
constructor(address tokenA, address tokenB) ;
```

