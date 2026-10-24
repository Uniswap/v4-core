// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CustomRevert} from "./CustomRevert.sol";

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
/// @dev These functions revert with SafeCastOverflow if the cast would result in data loss.
/// This library is essential for safely converting between different integer sizes in Uniswap v4,
/// particularly when working with packed storage formats and balance calculations.
library SafeCast {
    using CustomRevert for bytes4;

    /// @notice Thrown when a cast would overflow or underflow the target type
    error SafeCastOverflow();

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @dev Used for safely converting to address-sized integers (e.g., sqrtPriceX96 bounds)
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type uint160
    function toUint160(uint256 x) internal pure returns (uint160 y) {
        y = uint160(x);
        if (y != x) SafeCastOverflow.selector.revertWith();
    }

    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @dev Used for safely converting to liquidity amounts which are stored as uint128
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type uint128
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        y = uint128(x);
        if (x != y) SafeCastOverflow.selector.revertWith();
    }

    /// @notice Cast a int128 to a uint128, revert on overflow or underflow
    /// @dev Converts signed to unsigned, reverting if the input is negative
    /// @param x The int128 to be casted
    /// @return y The casted integer, now type uint128
    function toUint128(int128 x) internal pure returns (uint128 y) {
        if (x < 0) SafeCastOverflow.selector.revertWith();
        y = uint128(x);
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @dev Used when extracting int128 values from packed int256 representations
    /// @param x The int256 to be downcasted
    /// @return y The downcasted integer, now type int128
    function toInt128(int256 x) internal pure returns (int128 y) {
        y = int128(x);
        if (y != x) SafeCastOverflow.selector.revertWith();
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @dev Converts unsigned to signed, reverting if the value exceeds int256.max
    /// @param x The uint256 to be casted
    /// @return y The casted integer, now type int256
    function toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        if (y < 0) SafeCastOverflow.selector.revertWith();
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @dev Combines downcasting and sign conversion in one operation
    /// Reverts if x >= 2^127 (the maximum value of int128 + 1)
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type int128
    function toInt128(uint256 x) internal pure returns (int128 y) {
        if (x >= 1 << 127) SafeCastOverflow.selector.revertWith();
        y = int128(int256(x));
    }
}
