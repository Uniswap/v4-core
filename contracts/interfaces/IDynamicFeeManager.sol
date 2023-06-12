// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {IPoolManager} from "./IPoolManager.sol";

/// @notice The dynamic fee manager determines fees for pools
/// @dev note that this pool is only called if the PoolKey fee value is equal to the DYNAMIC_FEE magic value
interface IDynamicFeeManager {
    function getFee(IPoolManager.PoolKey calldata key) external returns (uint24);
}
