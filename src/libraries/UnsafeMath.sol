// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
library UnsafeMath {
    /// @notice Thrown when attempting to divide by zero
    error DivisionByZero();

    /// @notice Returns ceil(x / y)
    /// @dev Reverts if y is 0
    /// @param x The dividend
    /// @param y The divisor
    /// @return z The quotient, ceil(x / y)
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (y == 0) revert DivisionByZero();
        assembly ("memory-safe") {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    /// @notice Calculates floor(a×b÷denominator)
    /// @dev Reverts if denominator is 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return result The 256-bit result, floor(a×b÷denominator)
    function simpleMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        if (denominator == 0) revert DivisionByZero();
        assembly ("memory-safe") {
            result := div(mul(a, b), denominator)
        }
    }
}
