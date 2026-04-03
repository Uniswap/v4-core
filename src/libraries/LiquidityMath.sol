// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Math library for liquidity
/// @notice Provides utility functions for liquidity calculations in Uniswap v4
/// @dev This library handles safe arithmetic operations for liquidity amounts,
/// which are represented as uint128 values. The primary function addDelta
/// allows both adding and subtracting liquidity using a signed delta value.
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @dev This function safely handles both positive and negative deltas:
    /// - Positive delta: adds liquidity (minting)
    /// - Negative delta: removes liquidity (burning)
    /// Uses assembly for gas optimization and to handle edge cases with int128.min
    /// @param x The current liquidity before the change (uint128)
    /// @param y The delta by which liquidity should be changed (int128, can be negative)
    /// @return z The new liquidity after applying the delta
    /// @custom:error SafeCastOverflow Reverts if the result would overflow uint128 or underflow below 0
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            // Mask x to 128 bits and sign-extend y from 128 bits to 256 bits
            // signextend(15, y) extends the sign bit of byte 15 (the 128th bit) across the upper bits
            z := add(and(x, 0xffffffffffffffffffffffffffffffff), signextend(15, y))
            // Check if result exceeds uint128 max by checking if any bits above position 128 are set
            // If shr(128, z) is non-zero, the result overflowed uint128 bounds
            if shr(128, z) {
                // revert SafeCastOverflow()
                // Selector: 0x93dafdf1 = bytes4(keccak256("SafeCastOverflow()"))
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
        }
    }
}
