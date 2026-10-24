// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BeforeSwapDelta
/// @notice Return type of the beforeSwap hook that encodes two int128 values in a single int256
/// @dev The delta values are packed as follows:
/// - Upper 128 bits: delta in specified tokens (the token the user is swapping from)
/// - Lower 128 bits: delta in unspecified tokens (the token the user is swapping to)
/// This packing matches the afterSwap hook format for consistency.
/// Positive values indicate tokens owed TO the hook, negative values indicate tokens owed BY the hook.
type BeforeSwapDelta is int256;

/// @notice Creates a BeforeSwapDelta from specified and unspecified token deltas
/// @dev Packs two int128 values into a single int256 using bit manipulation.
/// The specified delta is shifted to the upper 128 bits, and the unspecified delta
/// occupies the lower 128 bits.
/// @param deltaSpecified The delta for the specified token (upper 128 bits)
/// @param deltaUnspecified The delta for the unspecified token (lower 128 bits)
/// @return beforeSwapDelta The packed BeforeSwapDelta value
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDelta beforeSwapDelta)
{
    assembly ("memory-safe") {
        // Pack: shift specified left by 128 bits, OR with masked unspecified
        // sub(shl(128, 1), 1) creates a 128-bit mask (0xFFFF...FFFF for lower 128 bits)
        beforeSwapDelta := or(shl(128, deltaSpecified), and(sub(shl(128, 1), 1), deltaUnspecified))
    }
}

/// @notice Library for getting the specified and unspecified deltas from the BeforeSwapDelta type
/// @dev Provides extraction functions to unpack the two int128 values from the packed int256
library BeforeSwapDeltaLibrary {
    /// @notice A BeforeSwapDelta of 0, representing no delta changes
    BeforeSwapDelta public constant ZERO_DELTA = BeforeSwapDelta.wrap(0);

    /// @notice Extracts the specified token delta from a BeforeSwapDelta
    /// @dev Extracts int128 from the upper 128 bits using arithmetic right shift.
    /// The arithmetic shift (sar) preserves the sign bit for negative values.
    /// @param delta The packed BeforeSwapDelta value
    /// @return deltaSpecified The specified token delta as int128
    function getSpecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaSpecified) {
        assembly ("memory-safe") {
            // Arithmetic right shift by 128 bits to get upper 128 bits with sign preservation
            deltaSpecified := sar(128, delta)
        }
    }

    /// @notice Extracts the unspecified token delta from a BeforeSwapDelta
    /// @dev Extracts int128 from the lower 128 bits using sign extension.
    /// signextend(15, delta) extends the sign bit at position 127 to fill upper bits.
    /// @param delta The packed BeforeSwapDelta value
    /// @return deltaUnspecified The unspecified token delta as int128
    function getUnspecifiedDelta(BeforeSwapDelta delta) internal pure returns (int128 deltaUnspecified) {
        assembly ("memory-safe") {
            // Sign extend from byte 15 (128th bit) to get signed lower 128 bits
            deltaUnspecified := signextend(15, delta)
        }
    }
}
