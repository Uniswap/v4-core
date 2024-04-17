// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @dev Equivalent to `z = y < 0 ? x - uint128(-y) : x + uint128(y);`
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity after
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := add(x, y)
            if shr(128, z) {
                // revert SafeCastOverflow()
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
        }
    }

    /// @notice Flips the sign of a liquidity delta if a condition is true
    /// @dev Equivalent to `res = flip ? -liquidityDelta : liquidityDelta;`
    /// @dev `liquidityDelta` should never be `type(int128).min`
    /// @param liquidityDelta The liquidity delta to potentially flip
    /// @param flip Whether to flip the sign of the liquidity delta
    /// @return res The potentially flipped liquidity delta
    function flipLiquidityDelta(int128 liquidityDelta, bool flip) internal pure returns (int128 res) {
        assembly {
            // if flip = true, res = -liquidityDelta = ~liquidityDelta + 1 = (-1) ^ liquidityDelta + 1
            // if flip = false, res = liquidityDelta = 0 ^ liquidityDelta + 0
            // therefore, res = (-flip) ^ liquidityDelta + flip
            res := add(xor(sub(0, flip), liquidityDelta), flip)
        }
    }
}
