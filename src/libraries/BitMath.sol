// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title BitMath
/// @dev This library provides functionality for computing bit properties of an unsigned integer
library BitMath {
    /// @notice Returns the index of the most significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @dev The function satisfies the property:
    ///     x >= 2**mostSignificantBit(x) and x < 2**(mostSignificantBit(x)+1)
    /// @dev Modified from [Solady](https://github.com/Vectorized/solady/blob/a6e41377a77084d6dc3cc54c34eb09e98c9f8204/src/utils/LibBit.sol#L16)
    /// @param x the value for which to compute the most significant bit, must be greater than 0
    /// @return r the index of the most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(x) { revert(0, 0) }

            // r = x >= 2**128 ? 128 : 0
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            // r += (x >> r) >= 2**64 ? 64 : 0
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            // r += (x >> r) >= 2**32 ? 32 : 0
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            // forgefmt: disable-next-item
            r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020504060203020504030106050205030304010505030400000000))
        }
    }

    /// @notice Returns the index of the least significant bit of the number,
    ///     where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @dev The function satisfies the property:
    ///     (x & 2**leastSignificantBit(x)) != 0 and (x & (2**(leastSignificantBit(x)) - 1)) == 0)
    /// @dev Modified from [Solady](https://github.com/Vectorized/solady/blob/a6e41377a77084d6dc3cc54c34eb09e98c9f8204/src/utils/LibBit.sol#L53)
    /// @param x the value for which to compute the least significant bit, must be greater than 0
    /// @return r the index of the least significant bit
    function leastSignificantBit(uint256 x) internal pure returns (uint8 r) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(x) { revert(0, 0) }

            // Isolate the least significant bit, x = x & -x = x & (~x + 1)
            x := and(x, sub(0, x))
            // For the upper 3 bits of the result, use a De Bruijn-like lookup.
            // Credit to adhusson: https://blog.adhusson.com/cheap-find-first-set-evm/
            // forgefmt: disable-next-item
            r := shl(5, shr(252, shl(shl(2, shr(250, mul(x,
                0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),
                0x8040405543005266443200005020610674053026020000107506200176117077)))
            // For the lower 5 bits of the result, use a De Bruijn lookup.
            // https://graphics.stanford.edu/~seander/bithacks.html#ZerosOnRightMultLookup
            // forgefmt: disable-next-item
            r := or(r, byte(and(div(0xd76453e0, shr(r, x)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
}
