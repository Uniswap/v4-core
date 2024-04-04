// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Math library for computing sqrt prices from ticks and vice versa
/// @notice Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports
/// prices between 2**-128 and 2**128
library TickMath {
    /// @notice Thrown when the tick passed to #getSqrtRatioAtTick is not between MIN_TICK and MAX_TICK
    error InvalidTick();
    /// @notice Thrown when the ratio passed to #getTickAtSqrtRatio does not correspond to a price between MIN_TICK and MAX_TICK
    error InvalidSqrtRatio();

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = 887272;

    /// @dev The minimum tick spacing value drawn from the range of type int16 that is greater than 0, i.e. min from the range [1, 32767]
    int24 internal constant MIN_TICK_SPACING = 1;
    /// @dev The maximum tick spacing value drawn from the range of type int16, i.e. max from the range [1, 32767]
    int24 internal constant MAX_TICK_SPACING = type(int16).max;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    /// @dev A threshold used for optimized bounds check, equals `MAX_SQRT_RATIO - MIN_SQRT_RATIO - 1`
    uint160 internal constant MAX_SQRT_RATIO_MINUS_MIN_SQRT_RATIO_MINUS_ONE =
        1461446703485210103287273052203988822378723970342 - 4295128739 - 1;

    /// @notice Given a tickSpacing, compute the maximum usable tick
    function maxUsableTick(int24 tickSpacing) internal pure returns (int24 tick) {
        assembly {
            tick := mul(div(MAX_TICK, tickSpacing), tickSpacing)
        }
    }

    /// @notice Given a tickSpacing, compute the minimum usable tick
    function minUsableTick(int24 tickSpacing) internal pure returns (int24 tick) {
        assembly {
            tick := mul(div(MIN_TICK, tickSpacing), tickSpacing)
        }
    }

    /// @notice Calculates sqrt(1.0001^tick) * 2^96
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (currency1/currency0)
    /// at the given tick
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            uint256 absTick;
            /// @solidity memory-safe-assembly
            assembly {
                // sign extend to make tick an int256 in twos complement
                tick := signextend(2, tick)
                // mask = 0 if tick >= 0 else -1
                let mask := sub(0, slt(tick, 0))
                // If tick >= 0, |tick| = tick = 0 ^ tick
                // If tick < 0, |tick| = ~~|tick| = ~(-|tick| - 1) = ~(tick - 1) = -1 ^ (tick - 1)
                // Either case, |tick| = mask ^ (tick + mask)
                absTick := xor(mask, add(mask, tick))
                // Equivalent: if (absTick > MAX_TICK) revert InvalidTick();
                if gt(absTick, MAX_TICK) {
                    // store 4-byte selector of "InvalidTick()" at memory [0x1c, 0x20)
                    mstore(0, 0xce8ef7fc)
                    revert(0x1c, 0x04)
                }
            }

            // Equivalent: ratio = 2**128 / sqrt(1.0001) if absTick & 0x1 else 1 << 128
            uint256 ratio;
            assembly {
                ratio :=
                    and(
                        shr(
                            // 128 if absTick & 0x1 else 0
                            shl(7, and(absTick, 0x1)),
                            // upper 128 bits of 2**256 / sqrt(1.0001) where the 128th bit is 1
                            0xfffcb933bd6fad37aa2d162d1a59400100000000000000000000000000000000
                        ),
                        0x1ffffffffffffffffffffffffffffffff // mask lower 129 bits
                    )
            }
            // Iterate through 1th to 19th bit of absTick because MAX_TICK < 2**20
            // Equivalent to:
            //      for i in range(1, 20):
            //          if absTick & 2 ** i:
            //              ratio = ratio * (2 ** 128 / 1.0001 ** (2 ** (i - 1))) / 2 ** 128
            if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

            // if (tick > 0) ratio = type(uint256).max / ratio;
            assembly {
                if sgt(tick, 0) { ratio := div(not(0), ratio) }
            }

            // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
            // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
            // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
            assembly {
                sqrtPriceX96 := shr(32, add(ratio, 0xffffffff))
            }
        }
    }

    /// @notice Calculates the greatest tick value such that getRatioAtTick(tick) <= ratio
    /// @dev Throws in case sqrtPriceX96 < MIN_SQRT_RATIO, as MIN_SQRT_RATIO is the lowest value getRatioAtTick may
    /// ever return.
    /// @param sqrtPriceX96 The sqrt ratio for which to compute the tick as a Q64.96
    /// @return tick The greatest tick for which the ratio is less than or equal to the input ratio
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // Equivalent: if (sqrtPriceX96 < MIN_SQRT_RATIO || sqrtPriceX96 >= MAX_SQRT_RATIO) revert InvalidSqrtRatio();
        // second inequality must be >= because the price can never reach the price at the max tick
        /// @solidity memory-safe-assembly
        assembly {
            // if sqrtPriceX96 < MIN_SQRT_RATIO, the `sub` underflows and `gt` is true
            // if sqrtPriceX96 >= MAX_SQRT_RATIO, sqrtPriceX96 - MIN_SQRT_RATIO > MAX_SQRT_RATIO - MAX_SQRT_RATIO - 1
            if gt(sub(sqrtPriceX96, MIN_SQRT_RATIO), MAX_SQRT_RATIO_MINUS_MIN_SQRT_RATIO_MINUS_ONE) {
                // store 4-byte selector of "InvalidSqrtRatio()" at memory [0x1c, 0x20)
                mstore(0, 0x02ad01b6)
                revert(0x1c, 0x04)
            }
        }

        // Find the most significant bit of `sqrtPriceX96`, 160 > msb >= 32.
        uint8 msb;
        assembly {
            let x := sqrtPriceX96
            msb := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            msb := or(msb, shl(6, lt(0xffffffffffffffff, shr(msb, x))))
            msb := or(msb, shl(5, lt(0xffffffff, shr(msb, x))))

            // For the remaining 32 bits, use a De Bruijn lookup.
            x := shr(msb, x)
            x := or(x, shr(1, x))
            x := or(x, shr(2, x))
            x := or(x, shr(4, x))
            x := or(x, shr(8, x))
            x := or(x, shr(16, x))

            msb :=
                or(
                    msb,
                    byte(
                        shr(251, mul(x, shl(224, 0x07c4acdd))),
                        0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f
                    )
                )
        }

        // 2**(msb - 95) > sqrtPrice >= 2**(msb - 96)
        // the integer part of log_2(sqrtPrice) * 2**64 = (msb - 96) << 64, 8.64 number
        int256 log_2X64;
        assembly {
            log_2X64 := shl(64, sub(msb, 96))

            // Get the first 128 significant figures of `sqrtPriceX96`.
            // r = sqrtPriceX96 / 2**(msb - 127), where 2**128 > r >= 2**127
            // sqrtPrice = 2**(msb - 96) * r / 2**127, in floating point math
            // Shift left first because 160 > msb >= 32. If we shift right first, we'll lose precision.
            let r := shr(sub(msb, 31), shl(96, sqrtPriceX96))

            // Check whether x >= sqrt(2) * 2**127 for 2**128 > x >= 2**127
            // This Yul function is declared but not used. Instead, it is inlined 14 times below.
            // However, due to solc's quirkiness, removing it results in higher gas.
            function ge_sqrt2X127(x) -> y, f {
                // 2**256 > x**2 >= 2**254
                let square := mul(x, x)
                // f = (x**2 >= 2**255)
                f := slt(square, 0)
                // y = x**2 >> 128 if x**2 >= 2**255 else x**2 >> 127
                y := shr(add(127, f), square)
            }

            // Approximate `log_2X64` to 14 binary digits after decimal
            let square := mul(r, r)
            let f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(63, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(62, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(61, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(60, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(59, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(58, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(57, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(56, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(55, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(54, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(53, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(52, f), log_2X64)

            square := mul(r, r)
            f := slt(square, 0)
            r := shr(add(127, f), square)
            log_2X64 := or(shl(51, f), log_2X64)

            log_2X64 := or(shl(50, slt(mul(r, r), 0)), log_2X64)
        }

        // sqrtPrice = sqrt(1.0001^tick)
        // tick = log_{sqrt(1.0001)}(sqrtPrice) = log_2(sqrtPrice) / log_2(sqrt(1.0001))
        // 2**64 / log_2(sqrt(1.0001)) = 255738958999603826347141
        int24 tickLow;
        int24 tickHi;
        assembly {
            let log_sqrt10001 := mul(log_2X64, 255738958999603826347141) // 128.128 number
            tickLow := shr(128, sub(log_sqrt10001, 3402992956809132418596140100660247210))
            tickHi := shr(128, add(log_sqrt10001, 291339464771989622907027621153398088495))
        }

        // Equivalent: tick = tickLow == tickHi ? tickLow : getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
        if (tickLow == tickHi) {
            return tickHi;
        }
        uint160 sqrtRatioAtTickHi = getSqrtRatioAtTick(tickHi);
        assembly {
            tick := sub(tickHi, gt(sqrtRatioAtTickHi, sqrtPriceX96))
        }
    }
}
