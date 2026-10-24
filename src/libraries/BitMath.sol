// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BitMath
/// @notice This library provides functionality for computing bit properties of an unsigned integer
/// @dev Provides gas-efficient methods for finding the most and least significant bits in a uint256.
/// These operations are fundamental for tick bitmap navigation in Uniswap v4's concentrated liquidity.
/// Both functions use optimized algorithms with De Bruijn sequences for O(1) bit manipulation.
/// @author Solady (https://github.com/Vectorized/solady/blob/8200a70e8dc2a77ecb074fc2e99a2a0d36547522/src/utils/LibBit.sol)
library BitMath {
    /// @notice Returns the index of the most significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @dev Uses a binary search approach combined with De Bruijn sequences for efficiency.
    /// The algorithm first narrows down which 128/64/32/16/8-bit section contains the MSB,
    /// then uses a De Bruijn lookup for the final precision.
    /// @param x the value for which to compute the most significant bit, must be greater than 0
    /// @return r the index of the most significant bit (0-255)
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        assembly ("memory-safe") {
            // Binary search: check if MSB is in upper half of remaining bits
            // lt(0xFFFF..., x) returns 1 if x > threshold, meaning MSB is in upper half
            // shl(7, ...) sets bit 7 (value 128) if MSB is in upper 128 bits
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            // Check upper 64 bits of remaining section
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            // Check upper 32 bits of remaining section
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            // Check upper 16 bits of remaining section
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            // Check upper 8 bits of remaining section
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // Final 8-bit precision: use De Bruijn-like lookup table for remaining bits
            // The magic numbers encode a compact lookup that maps bit patterns to bit indices
            // forgefmt: disable-next-item
            r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020500060203020504000106050205030304010505030400000000))
        }
    }

    /// @notice Returns the index of the least significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @dev First isolates the LSB using two's complement (x & -x), then uses De Bruijn multiplication
    /// to efficiently compute the bit index. This technique maps each power of 2 to a unique
    /// index in the lookup table.
    /// Credit to adhusson: https://blog.adhusson.com/cheap-find-first-set-evm/
    /// @param x the value for which to compute the least significant bit, must be greater than 0
    /// @return r the index of the least significant bit (0-255)
    function leastSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);

        assembly ("memory-safe") {
            // Isolate the least significant bit: x & (-x) = x & (two's complement of x)
            // This leaves only the rightmost 1 bit set
            x := and(x, sub(0, x))
            
            // De Bruijn multiplication technique for upper 3 bits (determines which 32-bit section)
            // The magic constant maps each power of 2 to a unique 3-bit section index
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            
            // De Bruijn lookup for lower 5 bits (precise position within the 32-bit section)
            // 0xd76453e0 is the De Bruijn constant, lookup table maps to exact bit position
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
}
