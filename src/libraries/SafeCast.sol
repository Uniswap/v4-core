// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    error SafeCastOverflow();

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint160
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        z = uint160(y);
        if (z != y) revert SafeCastOverflow();
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        z = int128(y);
        if (z != y) revert SafeCastOverflow();
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        if (y > uint256(type(int256).max)) revert SafeCastOverflow();
        z = int256(y);
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(uint256 y) internal pure returns (int128 z) {
        if (y > uint128(type(int128).max)) revert SafeCastOverflow();
        z = int128(int256(y));
    }

    /// @notice Flip the sign of an int128, revert on overflow
    /// @param y The int128 to flip the sign of
    /// @return The flipped integer, still an int128
    function flipSign(int128 y) internal pure returns (int128) {
        // this is not unchecked, so it will revert if y==type(int128).min
        return -y;
    }
}
