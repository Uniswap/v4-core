// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            z := add(and(x, 0xffffffffffffffffffffffffffffffff), signextend(15, y))
            if shr(128, z) {
                // revert SafeCastOverflow()
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
        }
    }
}
