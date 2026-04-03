// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "../libraries/SafeCast.sol";

/// @title BalanceDelta
/// @notice Represents the balance changes for a pool operation, encoding two int128 values in a single int256
/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
/// This packing is used throughout Uniswap v4 to efficiently pass balance deltas in a single word.
/// Positive values indicate tokens owed TO the caller, negative values indicate tokens owed BY the caller.
type BalanceDelta is int256;

using {add as +, sub as -, eq as ==, neq as !=} for BalanceDelta global;
using BalanceDeltaLibrary for BalanceDelta global;
using SafeCast for int256;

/// @notice Creates a BalanceDelta from two int128 amounts
/// @dev Packs amount0 into upper 128 bits and amount1 into lower 128 bits.
/// Uses assembly for gas-efficient bit manipulation.
/// @param _amount0 The balance delta for token0 (will be stored in upper 128 bits)
/// @param _amount1 The balance delta for token1 (will be stored in lower 128 bits)
/// @return balanceDelta The packed BalanceDelta value
function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta balanceDelta) {
    assembly ("memory-safe") {
        // Shift amount0 left by 128 bits to occupy upper half
        // Mask amount1 to 128 bits and OR with shifted amount0
        // sub(shl(128, 1), 1) creates a 128-bit mask (0xFFFF...FFFF)
        balanceDelta := or(shl(128, _amount0), and(sub(shl(128, 1), 1), _amount1))
    }
}

/// @notice Adds two BalanceDeltas together
/// @dev Extracts both components from each delta, adds them, then repacks.
/// Uses SafeCast to ensure the sums fit in int128.
/// @param a The first BalanceDelta
/// @param b The second BalanceDelta
/// @return The sum of the two BalanceDeltas
function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    int256 res0;
    int256 res1;
    assembly ("memory-safe") {
        // Extract amount0 from upper 128 bits using arithmetic right shift (preserves sign)
        let a0 := sar(128, a)
        // Extract amount1 from lower 128 bits using sign extension
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        // Sum the components
        res0 := add(a0, b0)
        res1 := add(a1, b1)
    }
    // SafeCast to int128 to ensure no overflow
    return toBalanceDelta(res0.toInt128(), res1.toInt128());
}

/// @notice Subtracts one BalanceDelta from another
/// @dev Extracts both components from each delta, subtracts them, then repacks.
/// Uses SafeCast to ensure the differences fit in int128.
/// @param a The BalanceDelta to subtract from
/// @param b The BalanceDelta to subtract
/// @return The difference of the two BalanceDeltas
function sub(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    int256 res0;
    int256 res1;
    assembly ("memory-safe") {
        // Extract amount0 from upper 128 bits using arithmetic right shift (preserves sign)
        let a0 := sar(128, a)
        // Extract amount1 from lower 128 bits using sign extension
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        // Subtract the components
        res0 := sub(a0, b0)
        res1 := sub(a1, b1)
    }
    // SafeCast to int128 to ensure no underflow
    return toBalanceDelta(res0.toInt128(), res1.toInt128());
}

/// @notice Checks if two BalanceDeltas are equal
/// @dev Compares the raw int256 values directly
/// @param a The first BalanceDelta
/// @param b The second BalanceDelta
/// @return True if both BalanceDeltas are equal
function eq(BalanceDelta a, BalanceDelta b) pure returns (bool) {
    return BalanceDelta.unwrap(a) == BalanceDelta.unwrap(b);
}

/// @notice Checks if two BalanceDeltas are not equal
/// @dev Compares the raw int256 values directly
/// @param a The first BalanceDelta
/// @param b The second BalanceDelta
/// @return True if the BalanceDeltas are not equal
function neq(BalanceDelta a, BalanceDelta b) pure returns (bool) {
    return BalanceDelta.unwrap(a) != BalanceDelta.unwrap(b);
}

/// @notice Library for getting the amount0 and amount1 deltas from the BalanceDelta type
/// @dev Provides extraction functions to unpack the two int128 values from the packed int256
library BalanceDeltaLibrary {
    /// @notice A BalanceDelta of 0, representing no balance change
    BalanceDelta public constant ZERO_DELTA = BalanceDelta.wrap(0);

    /// @notice Extracts the amount0 delta from a BalanceDelta
    /// @dev Uses arithmetic right shift to extract upper 128 bits with sign preservation
    /// @param balanceDelta The packed BalanceDelta value
    /// @return _amount0 The token0 balance delta as int128
    function amount0(BalanceDelta balanceDelta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            // Arithmetic right shift by 128 bits extracts upper 128 bits with sign extension
            _amount0 := sar(128, balanceDelta)
        }
    }

    /// @notice Extracts the amount1 delta from a BalanceDelta
    /// @dev Uses sign extension to extract lower 128 bits as a signed value
    /// @param balanceDelta The packed BalanceDelta value
    /// @return _amount1 The token1 balance delta as int128
    function amount1(BalanceDelta balanceDelta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            // signextend(15, x) extends the sign bit at byte 15 (bit 127) to fill upper bits
            _amount1 := signextend(15, balanceDelta)
        }
    }
}
