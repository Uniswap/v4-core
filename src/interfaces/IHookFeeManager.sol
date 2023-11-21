// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";

/// @notice The interface for setting a fee on swap or fee on withdraw to the hook
/// @dev This callback is only made if the Fee.HOOK_SWAP_FEE_FLAG or Fee.HOOK_WITHDRAW_FEE_FLAG in set in the pool's key.fee.
interface IHookFeeManager {
    /// @notice Gets the fee a hook can take at swap/withdraw. Upper bits used for swap and lower bits for withdraw.
    /// @param key The pool key
    /// @return The hook fees for swapping (upper bits set) and withdrawing (lower bits set).
    function getHookFees(PoolKey calldata key) external view returns (uint24);
}
