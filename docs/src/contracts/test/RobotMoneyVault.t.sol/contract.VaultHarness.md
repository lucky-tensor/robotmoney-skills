# VaultHarness
[Git Source](https://github.com/lucky-tensor/robotmoney-monorepo/blob/4657e0998ea86d624b2c44e64051b74c4f3664c9/contracts/test/RobotMoneyVault.t.sol)

**Inherits:**
[RobotMoneyVault](/contracts/RobotMoneyVault.sol/contract.RobotMoneyVault.md)

Exposes internal helpers for tests.


## Functions
### constructor


```solidity
constructor(
    IERC20 asset_,
    uint256 tvlCap_,
    uint256 perDepositCap_,
    uint256 exitFeeBps_,
    address feeRecipient_,
    address admin_
) RobotMoneyVault(asset_, tvlCap_, perDepositCap_, exitFeeBps_, feeRecipient_, admin_);
```

### exposed_decimalsOffset


```solidity
function exposed_decimalsOffset() external pure returns (uint8);
```

