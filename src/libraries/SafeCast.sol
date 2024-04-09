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
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(lt(y, shl(160, 1))) {
                // revert SafeCastOverflow();
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
            z := y
        }
    }

    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint128
    function toUint128(uint256 y) internal pure returns (uint128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(lt(y, shl(128, 1))) {
                // revert SafeCastOverflow();
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
            z := y
        }
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param y The int256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(eq(y, signextend(15, y))) {
                // revert SafeCastOverflow();
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
            z := y
        }
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if slt(y, 0) {
                // revert SafeCastOverflow();
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
            z := y
        }
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type int128
    function toInt128(uint256 y) internal pure returns (int128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(lt(y, shl(127, 1))) {
                // revert SafeCastOverflow();
                mstore(0, 0x93dafdf1)
                revert(0x1c, 0x04)
            }
            z := y
        }
    }
}
