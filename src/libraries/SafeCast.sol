// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    error SafeCastOverflow();

    function _revertOverflow() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            // Store the function selector of `SafeCastOverflow()`.
            mstore(0x00, 0x93dafdf1)
            // Revert with (offset, size).
            revert(0x1c, 0x04)
        }
    }

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint160
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        if (y >= 1 << 160) _revertOverflow();
        z = uint160(y);
    }

    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint128
    function toUint128(uint256 y) internal pure returns (uint128 z) {
        if (y >= 1 << 128) _revertOverflow();
        z = uint128(y);
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        if (y != int128(y)) _revertOverflow();
        z = int128(y);
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if slt(y, 0) {
                // Store the function selector of `SafeCastOverflow()`.
                mstore(0x00, 0x93dafdf1)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }
            z := y
        }
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(uint256 y) internal pure returns (int128 z) {
        if (y >= 1 << 127) _revertOverflow();
        z = int128(int256(y));
    }
}
