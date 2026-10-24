// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
/// @dev WARNING: This library is intentionally unsafe and should only be used when the caller
/// has already validated inputs or when the specific behavior (like returning 0 for division by 0)
/// is explicitly desired. For safe math operations, consider using FullMath or OpenZeppelin's Math.
/// The functions in this library are gas-optimized using inline assembly and skip safety checks
/// that would normally prevent undefined or erroneous behavior.
/// @custom:security-contact security@uniswap.org
library UnsafeMath {
    /// @notice Returns ceil(x / y)
    /// @dev WARNING: Division by 0 will return 0, not revert. This behavior should be checked externally.
    /// This function is useful when you've already validated that y != 0 and want to save gas on the check.
    /// @param x The dividend
    /// @param y The divisor (must be validated externally to be non-zero if a revert is desired)
    /// @return z The quotient, ceil(x / y), or 0 if y is 0
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            // Compute x / y + (x % y > 0 ? 1 : 0) to get ceiling division
            // gt(mod(x, y), 0) returns 1 if there's a remainder, 0 otherwise
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    /// @notice Calculates floor(a×b÷denominator)
    /// @dev WARNING: Division by 0 will return 0, not revert. This behavior should be checked externally.
    /// WARNING: This function can silently overflow if a * b > type(uint256).max.
    /// Use FullMath.mulDiv for cases where overflow is possible and must be handled correctly.
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor (must be validated externally to be non-zero if a revert is desired)
    /// @return result The 256-bit result, floor(a×b÷denominator), or 0 if denominator is 0
    function simpleMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            // Simple multiplication followed by division
            // WARNING: mul(a, b) can overflow, results in truncated lower 256 bits
            result := div(mul(a, b), denominator)
        }
    }
}
