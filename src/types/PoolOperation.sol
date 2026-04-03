// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

/// @notice Parameter struct for `ModifyLiquidity` pool operations
/// @dev Passed to modifyLiquidity to change the liquidity of a position
struct ModifyLiquidityParams {
    /// @notice The lower tick of the position
    int24 tickLower;
    /// @notice The upper tick of the position
    int24 tickUpper;
    /// @notice How to modify the liquidity
    /// @dev Positive value adds liquidity, negative value removes liquidity
    int256 liquidityDelta;
    /// @notice A value to set if you want unique liquidity positions at the same range
    /// @dev Allows distinguishing positions with the same ticks and owner
    bytes32 salt;
}

/// @notice Parameter struct for `Swap` pool operations
/// @dev Passed to swap to execute a trade
struct SwapParams {
    /// @notice Whether to swap token0 for token1 or vice versa
    /// @dev true for token0 -> token1, false for token1 -> token0
    bool zeroForOne;
    /// @notice The desired input amount if negative (exactIn), or the desired output amount if positive (exactOut)
    /// @dev Negative value means exact input (paying this amount), positive means exact output (receiving this amount)
    int256 amountSpecified;
    /// @notice The sqrt price at which, if reached, the swap will stop executing
    /// @dev Used for slippage protection or specific price targeting
    uint160 sqrtPriceLimitX96;
}
