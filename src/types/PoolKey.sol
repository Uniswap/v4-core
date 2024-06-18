// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Currency} from "./Currency.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "./../interfaces/IPoolManager.sol";

/// @notice Returns the key for identifying a pool
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @notice The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @notice The pool swap fee, capped at 1_000_000. If the first bit is 1, the pool has a dynamic fee and must be exactly equal to 0x800000
    uint24 fee;
    /// @notice Ticks that involve positions must be a multiple of tick spacing
    int24 tickSpacing;
    /// @notice The hooks of the pool
    IHooks hooks;
}

library PoolKeyLibrary {
    /// @notice Returns the unspecified currency and amount for a swap
    function getUnspecified(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency currencyUnspecified, int256 amountUnspecified)
    {
        bool currency0Specified = (params.amountSpecified < 0 == params.zeroForOne);
        return (currency0Specified) ? (key.currency1, params.amountSpecified) : (key.currency0, params.amountSpecified);
    }

    /// @notice Returns the specified currency and amount for a swap
    function getSpecified(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency currencySpecified, int256 amountSpecified)
    {
        bool currency0Specified = (params.amountSpecified < 0 == params.zeroForOne);
        return (currency0Specified) ? (key.currency0, params.amountSpecified) : (key.currency1, params.amountSpecified);
    }
}
