# BasketVaultHarness
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/b2783a9fccc37987f2403e8b51396991d9825f59/contracts/test/BasketVault.t.sol)

**Inherits:**
[BasketVault](/contracts/vaults/BasketVault.sol/abstract.BasketVault.md)


## Functions
### constructor


```solidity
constructor(IERC20 usdc_, ISwapRouter swapRouter_, address admin_)
    BasketVault(
        "Basket Harness",
        "bTEST",
        usdc_,
        swapRouter_,
        1_000_000e6,
        100_000e6,
        0,
        100,
        admin_,
        admin_
    );
```

### maxAssets


```solidity
function maxAssets() public pure override returns (uint256);
```

