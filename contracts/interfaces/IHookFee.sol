// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IPoolManager} from "./IPoolManager.sol";

/// @notice The interface for setting a fee to the hook
/// @dev note that this pool is only called if the hook's address setFee flag is true
interface IHookFee {
    function getHookFee(IPoolManager.PoolKey calldata key) external view returns (uint8);
}
