// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {BitMath} from "./BitMath.sol";

/// @dev Uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values
/// per word. On its own the struct is just a storage pointer, the library gives mapping
/// capabilities.
/// @notice Stores a packed mapping of tick index to its initialized state
struct TickBitmap {
    // Ensures the struct isn't empty and is assigned a slot by the compiler.
    uint256 __placeholder;
}

using TickBitmapLibrary for TickBitmap global;

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev Implementation and core utility methods for `TickBitmap`.
library TickBitmapLibrary {
    /// @notice Thrown when the tick is not enumerated by the tick spacing
    /// @param tick the invalid tick
    /// @param tickSpacing The tick spacing of the pool
    error TickMisaligned(int24 tick, int24 tickSpacing);

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        unchecked {
            wordPos = int16(tick >> 8);
            bitPos = uint8(int8(tick & (256 - 1)));
        }
    }

    /// @notice Retrieves a word from the bitmap.
    /// @param self The mapping in which to flip the tick.
    /// @param wordPos The offset in the mapping from which to retrieve the word.
    /// @return word The bitmap word.
    function get(TickBitmap storage self, int16 wordPos) internal view returns (uint256 word) {
        assembly ("memory-safe") {
            // Compute the word's slot.
            mstore(0, self.slot)
            let slot := add(keccak256(0, 32), wordPos)
            word := sload(slot)
        }
    }

    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(TickBitmap storage self, int24 tick, int24 tickSpacing) internal {
        unchecked {
            if (tick % tickSpacing != 0) revert TickMisaligned(tick, tickSpacing); // ensure that the tick is spaced
            (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
            uint256 mask = 1 << bitPos;
            assembly ("memory-safe") {
                // Compute the word's slot.
                mstore(0x00, self.slot)
                let slot := add(keccak256(0x00, 0x20), wordPos)
                // Update the word using the mask.
                let word := sload(slot)
                sstore(slot, xor(word, mask))
            }
        }
    }

    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(TickBitmap storage self, int24 tick, int24 tickSpacing, bool lte)
        internal
        view
        returns (int24 next, bool initialized)
    {
        unchecked {
            int24 compressed = tick / tickSpacing;
            if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

            if (lte) {
                (int16 wordPos, uint8 bitPos) = position(compressed);
                // all the 1s at or to the right of the current bitPos
                uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
                uint256 masked = self.get(wordPos) & mask;

                // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                    : (compressed - int24(uint24(bitPos))) * tickSpacing;
            } else {
                // start from the word of the next tick, since the current tick state doesn't matter
                (int16 wordPos, uint8 bitPos) = position(compressed + 1);
                // all the 1s at or to the left of the bitPos
                uint256 mask = ~((1 << bitPos) - 1);
                uint256 masked = self.get(wordPos) & mask;

                // if there are no initialized ticks to the left of the current tick, return leftmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
                    : (compressed + 1 + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
            }
        }
    }
}
