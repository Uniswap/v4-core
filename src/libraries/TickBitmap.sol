// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {BitMath} from "./BitMath.sol";

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickBitmap {
    /// @notice Thrown when the tick is not enumerated by the tick spacing
    /// @param tick the invalid tick
    /// @param tickSpacing The tick spacing of the pool
    error TickMisaligned(int24 tick, int24 tickSpacing);

    /// @dev round towards negative infinity
    function compress(int24 tick, int24 tickSpacing) internal pure returns (int24 compressed) {
        // compressed = tick / tickSpacing;
        // if (tick < 0 && tick % tickSpacing != 0) compressed--;
        assembly {
            compressed :=
                sub(
                    sdiv(tick, tickSpacing),
                    // if (tick < 0 && tick % tickSpacing != 0) then tick % tickSpacing < 0, vice versa
                    slt(smod(tick, tickSpacing), 0)
                )
        }
    }

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        assembly {
            // signed arithmetic shift right
            wordPos := sar(8, tick)
            bitPos := and(tick, 0xff)
        }
    }

    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        assembly ("memory-safe") {
            // ensure that the tick is spaced
            if smod(tick, tickSpacing) {
                mstore(0, 0xd4d8f3e6)
                mstore(0x20, tick)
                mstore(0x40, tickSpacing)
                revert(0x1c, 0x44)
            }
            tick := sdiv(tick, tickSpacing)
            // calculate the storage slot corresponding to the tick
            // wordPos = tick >> 8
            mstore(0, sar(8, tick))
            mstore(0x20, self.slot)
            // the slot of self[wordPos] is keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (tick % 256)
            // self[wordPos] ^= mask
            sstore(slot, xor(sload(slot), shl(and(tick, 0xff), 1)))
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
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = compress(tick, tickSpacing);

            if (!lte) {
                // start from the word of the next tick, since the current tick state doesn't matter
                (int16 wordPos, uint8 bitPos) = position(++compressed);
                // all the 1s at or to the left of the bitPos
                uint256 masked;
                assembly ("memory-safe") {
                    // mask = ~((1 << bitPos) - 1) = -((1 << bitPos) - 1) - 1 = -(1 << bitPos)
                    let mask := sub(0, shl(bitPos, 1))
                    // masked = self[wordPos] & mask
                    mstore(0, wordPos)
                    mstore(0x20, self.slot)
                    masked := and(sload(keccak256(0, 0x40)), mask)
                }

                // if there are no initialized ticks to the left of the current tick, return leftmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                if (!initialized) {
                    assembly {
                        next := mul(add(sub(compressed, bitPos), 255), tickSpacing)
                    }
                } else {
                    uint8 lsb = BitMath.leastSignificantBit(masked);
                    assembly {
                        next := mul(add(sub(compressed, bitPos), lsb), tickSpacing)
                    }
                }
            } else {
                (int16 wordPos, uint8 bitPos) = position(compressed);
                // all the 1s at or to the right of the current bitPos
                uint256 masked;
                assembly ("memory-safe") {
                    // mask = (1 << (bitPos + 1)) - 1
                    // (bitPos + 1) may overflow but fine since 1 << 256 = 0
                    let mask := sub(shl(add(bitPos, 1), 1), 1)
                    // masked = self[wordPos] & mask
                    mstore(0, wordPos)
                    mstore(0x20, self.slot)
                    masked := and(sload(keccak256(0, 0x40)), mask)
                }

                // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                if (!initialized) {
                    assembly {
                        next := mul(sub(compressed, bitPos), tickSpacing)
                    }
                } else {
                    uint8 msb = BitMath.mostSignificantBit(masked);
                    assembly {
                        next := mul(add(sub(compressed, bitPos), msb), tickSpacing)
                    }
                }
            }
        }
    }
}
