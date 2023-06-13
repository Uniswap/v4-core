// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {IPoolManager} from "./IPoolManager.sol";

/// @notice The interface for setting a fee on swap or fee on withdraw to the hook
/// @dev This callback is only made if the Fee.HOOK_SWAP_FEE_FLAG or Fee.HOOK_WITHDRAW_FEE_FLAG in set in the pool's key.fee.
interface IHookFeeManager {
    /// @notice Sets the fee a hook can take at swap.
    /// @param key The pool key
    /// @return The fee as an integer denominator for 1 to 0 swaps (upper bits set) or 0 to 1 swaps (lower bits set).
    function getHookSwapFee(IPoolManager.PoolKey calldata key) external view returns (uint8);

    /// @notice Sets the fee a hook can take at withdraw.
    /// @param key The pool key
    /// @return The fee as an integer denominator for amount1 (upper bits set) or amount0 (lower bits set).
    function getHookWithdrawFee(IPoolManager.PoolKey calldata key) external view returns (uint8);
}
