// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {IPoolManager} from "./IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

/// @notice The PoolManager contract decides whether to invoke specific hooks by inspecting the leading bits
/// of the hooks contract address. For example, a 1 bit in the first bit of the address will
/// cause the 'before swap' hook to be invoked. See the Hooks library for the full spec.
/// @dev Should only be callable by the v4 PoolManager.
interface IHooks {
    /// @notice The hook called before the state of a pool is initialized
    /// @param sender The initial msg.sender for the initialize call
    /// @param key The key for the pool being initialized
    /// @param sqrtPriceX96 The sqrt(price) of the pool as a Q64.96
    /// @return bytes4 The function selector for the hook
    function beforeInitialize(address sender, IPoolManager.PoolKey calldata key, uint160 sqrtPriceX96)
        external
        returns (bytes4);

    /// @notice The hook called after the state of a pool is initialized
    /// @param sender The initial msg.sender for the initialize call
    /// @param key The key for the pool being initialized
    /// @param sqrtPriceX96 The sqrt(price) of the pool as a Q64.96
    /// @param tick The current tick after the state of a pool is initialized
    /// @return bytes4 The function selector for the hook
    function afterInitialize(address sender, IPoolManager.PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        returns (bytes4);

    /// @notice The hook called before a position is modified
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for modifying the position
    /// @return bytes4 The function selector for the hook
    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external returns (bytes4);

    /// @notice The hook called after a position is modified
    /// @param sender The initial msg.sender for the modify position call
    /// @param key The key for the pool
    /// @param params The parameters for modifying the position
    /// @return bytes4 The function selector for the hook
    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        BalanceDelta delta
    ) external returns (bytes4);

    /// @notice The hook called before a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param params The parameters for the swap
    /// @return bytes4 The function selector for the hook
    function beforeSwap(address sender, IPoolManager.PoolKey calldata key, IPoolManager.SwapParams calldata params)
        external
        returns (bytes4);

    /// @notice The hook called after a swap
    /// @param sender The initial msg.sender for the swap call
    /// @param key The key for the pool
    /// @param params The parameters for the swap
    /// @param delta The amount owed to the locker (positive) or owed to the pool (negative)
    /// @return bytes4 The function selector for the hook
    function afterSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta
    ) external returns (bytes4);

    /// @notice The hook called before donate
    /// @param sender The initial msg.sender for the donate call
    /// @param key The key for the pool
    /// @param amount0 The amount of token0 being donated
    /// @param amount1 The amount of token1 being donated
    /// @return bytes4 The function selector for the hook
    function beforeDonate(address sender, IPoolManager.PoolKey calldata key, uint256 amount0, uint256 amount1)
        external
        returns (bytes4);

    /// @notice The hook called after donate
    /// @param sender The initial msg.sender for the donate call
    /// @param key The key for the pool
    /// @param amount0 The amount of token0 being donated
    /// @param amount1 The amount of token1 being donated
    /// @return bytes4 The function selector for the hook
    function afterDonate(address sender, IPoolManager.PoolKey calldata key, uint256 amount0, uint256 amount1)
        external
        returns (bytes4);
}
