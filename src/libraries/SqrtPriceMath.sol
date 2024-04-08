// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {SafeCast} from "./SafeCast.sol";

import {FullMath} from "./FullMath.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {FixedPoint96} from "./FixedPoint96.sol";

/// @title Functions based on Q64.96 sqrt price and liquidity
/// @notice Contains the math that uses square root of price as a Q64.96 and liquidity to compute deltas
library SqrtPriceMath {
    using SafeCast for uint256;
    using UnsafeMath for *;

    error InvalidPriceOrLiquidity();
    error InvalidPrice();
    error NotEnoughLiquidity();
    error PriceOverflow();

    /// @notice Gets the next sqrt price given a delta of currency0
    /// @dev Always rounds up, because in the exact output case (increasing price) we need to move the price at least
    /// far enough to get the desired output amount, and in the exact input case (decreasing price) we need to move the
    /// price less in order to not send too much output.
    /// The most precise formula for this is liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96),
    /// if this is impossible because of overflow, we calculate liquidity / (liquidity / sqrtPX96 +- amount).
    /// @param sqrtPX96 The starting price, i.e. before accounting for the currency0 delta
    /// @param liquidity The amount of usable liquidity
    /// @param amount How much of currency0 to add or remove from virtual reserves
    /// @param add Whether to add or remove the amount of currency0
    /// @return The price after adding or removing amount, depending on add
    function getNextSqrtPriceFromAmount0RoundingUp(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (uint160)
    {
        // we short circuit amount == 0 because the result is otherwise not guaranteed to equal the input price
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            unchecked {
                uint256 product = amount * sqrtPX96;
                // checks for overflow
                if (product.div(amount) == sqrtPX96) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        // always fits in 160 bits
                        return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
                    }
                }
            }
            // denominator is checked for overflow
            return uint160(numerator1.divRoundingUp(numerator1.div(sqrtPX96) + amount));
        } else {
            unchecked {
                uint256 product = amount * sqrtPX96;
                // if the product overflows, we know the denominator underflows
                // in addition, we must check that the denominator does not underflow
                if (!(product.div(amount) == sqrtPX96 && numerator1 > product)) revert PriceOverflow();
                uint256 denominator = numerator1 - product;
                return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
            }
        }
    }

    /// @notice Gets the next sqrt price given a delta of currency1
    /// @dev Always rounds down, because in the exact output case (decreasing price) we need to move the price at least
    /// far enough to get the desired output amount, and in the exact input case (increasing price) we need to move the
    /// price less in order to not send too much output.
    /// The formula we compute is within <1 wei of the lossless version: sqrtPX96 +- amount / liquidity
    /// @param sqrtPX96 The starting price, i.e., before accounting for the currency1 delta
    /// @param liquidity The amount of usable liquidity
    /// @param amount How much of currency1 to add, or remove, from virtual reserves
    /// @param add Whether to add, or remove, the amount of currency1
    /// @return The price after adding or removing `amount`
    function getNextSqrtPriceFromAmount1RoundingDown(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (uint160)
    {
        // if we're adding (subtracting), rounding down requires rounding the quotient down (up)
        // in both cases, avoid a mulDiv for most inputs
        if (add) {
            uint256 quotient = (
                amount >> 160 == 0
                    ? (amount << FixedPoint96.RESOLUTION).div(liquidity)
                    : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
            );

            return (uint256(sqrtPX96) + quotient).toUint160();
        } else {
            uint256 quotient = (
                amount >> 160 == 0
                    ? (amount << FixedPoint96.RESOLUTION).divRoundingUp(liquidity)
                    : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
            );

            if (sqrtPX96 <= quotient) revert NotEnoughLiquidity();
            // always fits 160 bits
            unchecked {
                return uint160(sqrtPX96 - quotient);
            }
        }
    }

    /// @notice Gets the next sqrt price given an input amount of currency0 or currency1
    /// @dev Throws if price or liquidity are 0, or if the next price is out of bounds
    /// @param sqrtPX96 The starting price, i.e., before accounting for the input amount
    /// @param liquidity The amount of usable liquidity
    /// @param amountIn How much of currency0, or currency1, is being swapped in
    /// @param zeroForOne Whether the amount in is currency0 or currency1
    /// @return sqrtQX96 The price after adding the input amount to currency0 or currency1
    function getNextSqrtPriceFromInput(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        internal
        pure
        returns (uint160 sqrtQX96)
    {
        if (sqrtPX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();

        // round to make sure that we don't pass the target price
        return zeroForOne
            ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
            : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @notice Gets the next sqrt price given an output amount of currency0 or currency1
    /// @dev Throws if price or liquidity are 0 or the next price is out of bounds
    /// @param sqrtPX96 The starting price before accounting for the output amount
    /// @param liquidity The amount of usable liquidity
    /// @param amountOut How much of currency0, or currency1, is being swapped out
    /// @param zeroForOne Whether the amount out is currency0 or currency1
    /// @return sqrtQX96 The price after removing the output amount of currency0 or currency1
    function getNextSqrtPriceFromOutput(uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        internal
        pure
        returns (uint160 sqrtQX96)
    {
        if (sqrtPX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();

        // round to make sure that we pass the target price
        return zeroForOne
            ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
            : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }

    /// @notice Sorts two `uint160`s and returns them in ascending order
    function sort2(uint160 a, uint160 b) internal pure returns (uint160, uint160) {
        assembly {
            let diff := mul(xor(a, b), lt(b, a))
            a := xor(a, diff)
            b := xor(b, diff)
        }
        return (a, b);
    }

    /// @notice Gets the amount0 delta between two prices
    /// @dev Calculates liquidity / sqrt(lower) - liquidity / sqrt(upper),
    /// i.e. liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up or down
    /// @return amount0 Amount of currency0 required to cover a position of size liquidity between the two passed prices
    function getAmount0Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount0)
    {
        (sqrtRatioAX96, sqrtRatioBX96) = sort2(sqrtRatioAX96, sqrtRatioBX96);

        if (sqrtRatioAX96 == 0) revert InvalidPrice();

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96.sub(sqrtRatioAX96);
        /**
         * Equivalent to:
         *   roundUp
         *       ? FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96).divRoundingUp(sqrtRatioAX96)
         *       : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
         * If `md = mulDiv(n1, n2, srb) == mulDivRoundingUp(n1, n2, srb)`, then `mulmod(n1, n2, srb) == 0`.
         * Add `roundUp && md % sra > 0` to `div(md, sra)`.
         * If `md = mulDiv(n1, n2, srb)` and `mulDivRoundingUp(n1, n2, srb)` differs by 1 and `sra > 0`,
         * then `(md + 1).divRoundingUp(sra) == md.div(sra) + 1` whether `sra` fully divides `md` or not.
         */
        uint256 mulDivResult = FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96);
        assembly {
            amount0 :=
                add(
                    div(mulDivResult, sqrtRatioAX96),
                    and(gt(or(mod(mulDivResult, sqrtRatioAX96), mulmod(numerator1, numerator2, sqrtRatioBX96)), 0), roundUp)
                )
        }
    }

    /// @notice Equivalent to: `a > b ? a - b : b - a`
    function absDiff(uint160 a, uint160 b) internal pure returns (uint256 res) {
        assembly {
            let diff := sub(a, b)
            let mask := sub(0, slt(diff, 0))
            res := xor(mask, add(mask, diff))
        }
    }

    /// @notice Gets the amount1 delta between two prices
    /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up, or down
    /// @return amount1 Amount of currency1 required to cover a position of size liquidity between the two passed prices
    function getAmount1Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount1)
    {
        uint256 numerator = absDiff(sqrtRatioAX96, sqrtRatioBX96);
        uint256 denominator = FixedPoint96.Q96;
        /**
         * Equivalent to:
         *   amount1 = roundUp
         *       ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
         *       : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
         * Cannot overflow because `type(uint128).max * type(uint160).max >> 96 < (1 << 192)`.
         */
        amount1 = FullMath.mulDivQ96(liquidity, numerator);
        assembly {
            amount1 := add(amount1, and(gt(mulmod(liquidity, numerator, denominator), 0), roundUp))
        }
    }

    /// @notice Helper that gets signed currency0 delta
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount0 delta
    /// @return amount0 Amount of currency0 corresponding to the passed liquidityDelta between the two prices
    function getAmount0Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        internal
        pure
        returns (int256 amount0)
    {
        /**
         * Equivalent to:
         *   amount0 = liquidity < 0
         *       ? getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
         *       : -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
         */
        bool sign;
        uint128 liquidityAbs;
        assembly {
            // In case the upper bits are not clean.
            liquidity := signextend(15, liquidity)
            // sign = 1 if liquidity >= 0 else 0
            sign := iszero(slt(liquidity, 0))
            // mask = 0 if liquidity >= 0 else -1
            let mask := sub(sign, 1)
            liquidityAbs := xor(mask, add(mask, liquidity))
        }
        // amount0Abs = liquidity / sqrt(lower) - liquidity / sqrt(upper) < type(uint224).max
        // always fits in 224 bits, no need for toInt256()
        uint256 amount0Abs = getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidityAbs, sign);
        assembly {
            // mask = -1 if liquidity >= 0 else 0
            let mask := sub(0, sign)
            // If liquidity < 0, amount0 = |amount0| = 0 ^ |amount0|
            // If liquidity >= 0, amount0 = -|amount0| = ~|amount0| + 1 = (-1) ^ |amount0| - (-1)
            amount0 := sub(xor(amount0Abs, mask), mask)
        }
    }

    /// @notice Helper that gets signed currency1 delta
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount1 delta
    /// @return amount1 Amount of currency1 corresponding to the passed liquidityDelta between the two prices
    function getAmount1Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        internal
        pure
        returns (int256 amount1)
    {
        /**
         * Equivalent to:
         *   amount1 = liquidity < 0
         *       ? getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
         *       : -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
         */
        bool sign;
        uint128 liquidityAbs;
        assembly {
            // In case the upper bits are not clean.
            liquidity := signextend(15, liquidity)
            // sign = 1 if liquidity >= 0 else 0
            sign := iszero(slt(liquidity, 0))
            // mask = 0 if liquidity >= 0 else -1
            let mask := sub(sign, 1)
            liquidityAbs := xor(mask, add(mask, liquidity))
        }
        // amount1Abs = liquidity * (sqrt(upper) - sqrt(lower)) < type(uint192).max
        // always fits in 192 bits, no need for toInt256()
        uint256 amount1Abs = getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidityAbs, sign);
        assembly {
            // mask = -1 if liquidity >= 0 else 0
            let mask := sub(0, sign)
            // If liquidity < 0, amount1 = |amount1| = 0 ^ |amount1|
            // If liquidity >= 0, amount1 = -|amount1| = ~|amount1| + 1 = (-1) ^ |amount1| - (-1)
            amount1 := sub(xor(amount1Abs, mask), mask)
        }
    }
}
