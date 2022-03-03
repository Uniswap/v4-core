// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.12;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {

    /// @notice Thrown when downcasted value does not equal the original value
    error DowncastInvalid();

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint160
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        if((z = uint160(y)) != y) revert DowncastInvalid();
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        if((z = int128(y)) != y) revert DowncastInvalid();
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        if (y >= 2**255) revert DowncastInvalid();
        z = int256(y);
    }
}
