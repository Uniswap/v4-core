// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IPoolManager} from "./IPoolManager.sol";

/// @notice The interface for setting a fee on swap to the hook
/// @dev note that this pool is only called if the PoolKey customFee flag is true
interface IHookFeeManager {
    function getHookFee(IPoolManager.PoolKey calldata) external view returns (uint8);
}
