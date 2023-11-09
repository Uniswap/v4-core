// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "./IPoolManager.sol";

/// @notice The dynamic fee manager determines fees for pools
/// @dev note that this pool is only called if the PoolKey fee value is equal to the DYNAMIC_FEE magic value
interface IDynamicFeeManager {
    function getFee(address sender, PoolKey calldata key) external view returns (uint24);
}
