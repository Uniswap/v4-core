// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Math functions that operate between a mix of signed and unsigned types
library UnsignedSignedMath {
    /// @notice Returns x + y
    /// @dev If y is negative x will decrease else increase
    function add(uint128 x, int128 y) internal pure returns (uint128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Add x and y and truncate result to 128-bits.
            z := shr(128, shl(128, add(x, y)))

            // Check that no overflow or underflow occured. Which is detected by checking if the
            // change in `z` relative to `x` is opposite of the direction indicated by the sign of
            // `y`.
            if iszero(eq(gt(z, x), sgt(y, 0))) {
                // Emit a standard overflow/underflow error (`Panic(0x11)`).
                mstore(0x00, 0x4e487b71)
                mstore(0x20, 0x11)
                revert(0x1c, 0x24)
            }
        }
    }

    /// @notice Returns x - y
    /// @dev If y is negative x will decrease else increase
    function sub(uint128 x, int128 y) internal pure returns (uint128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Add x and y and truncate result to 128-bits.
            z := shr(128, shl(128, sub(x, y)))

            // Check that no overflow or underflow occured. Which is detected by checking if the
            // change in `z` relative to `x` is not in the opposite direction dictated by the sign
            // of `y`.
            if iszero(eq(gt(z, x), slt(y, 0))) {
                // Emit a standard overflow/underflow error (`Panic(0x11)`).
                mstore(0x00, 0x4e487b71)
                mstore(0x20, 0x11)
                revert(0x1c, 0x24)
            }
        }
    }
}
