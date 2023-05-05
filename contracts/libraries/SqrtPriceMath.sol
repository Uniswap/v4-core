// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SafeCast} from "./SafeCast.sol";

import {FullMath} from "./FullMath.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {UQ64x96, FixedPoint96} from "./FixedPoint96.sol";

/// @title Functions based on Q64.96 sqrt price and liquidity
/// @notice Contains the math that uses square root of price as a Q64.96 and liquidity to compute deltas
library SqrtPriceMath {
    using SafeCast for uint256;
    using FixedPoint96 for UQ64x96;

    /// @notice Gets the next sqrt price given a delta of currency0
    /// @dev Always rounds up, because in the exact output case (increasing price) we need to move the price at least
    /// far enough to get the desired output amount, and in the exact input case (decreasing price) we need to move the
    /// price less in order to not send too much output.
    /// The most precise formula for this is liquidity * sqrtPrice / (liquidity +- amount * sqrtPrice),
    /// if this is impossible because of overflow, we calculate liquidity / (liquidity / sqrtPrice +- amount).
    /// @param sqrtPrice The starting price, i.e. before accounting for the currency0 delta
    /// @param liquidity The amount of usable liquidity
    /// @param amount How much of currency0 to add or remove from virtual reserves
    /// @param add Whether to add or remove the amount of currency0
    /// @return The price after adding or removing amount, depending on add
    function getNextSqrtPriceFromAmount0RoundingUp(UQ64x96 sqrtPrice, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (UQ64x96)
    {
        // we short circuit amount == 0 because the result is otherwise not guaranteed to equal the input price
        if (amount == 0) return sqrtPrice;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            unchecked {
                uint256 product;
                if ((product = amount * sqrtPrice.toUint256()) / amount == sqrtPrice.toUint256()) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        // always fits in 160 bits
                        return UQ64x96.wrap(
                            uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPrice.toUint256(), denominator))
                        );
                    }
                }
                // denominator is checked for overflow
                return UQ64x96.wrap(
                    uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPrice.toUint256()) + amount))
                );
            }
        } else {
            unchecked {
                uint256 product;
                // if the product overflows, we know the denominator underflows
                // in addition, we must check that the denominator does not underflow
                require(
                    (product = amount * sqrtPrice.toUint256()) / amount == sqrtPrice.toUint256() && numerator1 > product
                );
                uint256 denominator = numerator1 - product;
                return
                    UQ64x96.wrap(FullMath.mulDivRoundingUp(numerator1, sqrtPrice.toUint256(), denominator).toUint160());
            }
        }
    }

    /// @notice Gets the next sqrt price given a delta of currency1
    /// @dev Always rounds down, because in the exact output case (decreasing price) we need to move the price at least
    /// far enough to get the desired output amount, and in the exact input case (increasing price) we need to move the
    /// price less in order to not send too much output.
    /// The formula we compute is within <1 wei of the lossless version: sqrtPrice +- amount / liquidity
    /// @param sqrtPrice The starting price, i.e., before accounting for the currency1 delta
    /// @param liquidity The amount of usable liquidity
    /// @param amount How much of currency1 to add, or remove, from virtual reserves
    /// @param add Whether to add, or remove, the amount of currency1
    /// @return The price after adding or removing `amount`
    function getNextSqrtPriceFromAmount1RoundingDown(UQ64x96 sqrtPrice, uint128 liquidity, uint256 amount, bool add)
        internal
        pure
        returns (UQ64x96)
    {
        // if we're adding (subtracting), rounding down requires rounding the quotient down (up)
        // in both cases, avoid a mulDiv for most inputs
        if (add) {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? (amount << FixedPoint96.RESOLUTION) / liquidity
                    : FullMath.mulDiv(amount, FixedPoint96.ONE, liquidity)
            );

            return UQ64x96.wrap((sqrtPrice.toUint256() + quotient).toUint160());
        } else {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
                    : FullMath.mulDivRoundingUp(amount, FixedPoint96.ONE, liquidity)
            );

            require(sqrtPrice.toUint256() > quotient);
            // always fits 160 bits
            return UQ64x96.wrap(uint160(sqrtPrice.toUint256() - quotient));
        }
    }

    /// @notice Gets the next sqrt price given an input amount of currency0 or currency1
    /// @dev Throws if price or liquidity are 0, or if the next price is out of bounds
    /// @param sqrtPrice The starting price, i.e., before accounting for the input amount
    /// @param liquidity The amount of usable liquidity
    /// @param amountIn How much of currency0, or currency1, is being swapped in
    /// @param zeroForOne Whether the amount in is currency0 or currency1
    /// @return sqrtPriceAfter The price after adding the input amount to currency0 or currency1
    function getNextSqrtPriceFromInput(UQ64x96 sqrtPrice, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        internal
        pure
        returns (UQ64x96 sqrtPriceAfter)
    {
        require(sqrtPrice > UQ64x96.wrap(0));
        require(liquidity > 0);

        // round to make sure that we don't pass the target price
        return zeroForOne
            ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPrice, liquidity, amountIn, true)
            : getNextSqrtPriceFromAmount1RoundingDown(sqrtPrice, liquidity, amountIn, true);
    }

    /// @notice Gets the next sqrt price given an output amount of currency0 or currency1
    /// @dev Throws if price or liquidity are 0 or the next price is out of bounds
    /// @param sqrtPrice The starting price before accounting for the output amount
    /// @param liquidity The amount of usable liquidity
    /// @param amountOut How much of currency0, or currency1, is being swapped out
    /// @param zeroForOne Whether the amount out is currency0 or currency1
    /// @return sqrtPriceAfter The price after removing the output amount of currency0 or currency1
    function getNextSqrtPriceFromOutput(UQ64x96 sqrtPrice, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        internal
        pure
        returns (UQ64x96 sqrtPriceAfter)
    {
        require(sqrtPrice > UQ64x96.wrap(0));
        require(liquidity > 0);

        // round to make sure that we pass the target price
        return zeroForOne
            ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPrice, liquidity, amountOut, false)
            : getNextSqrtPriceFromAmount0RoundingUp(sqrtPrice, liquidity, amountOut, false);
    }

    /// @notice Gets the amount0 delta between two prices
    /// @dev Calculates liquidity / sqrt(lower) - liquidity / sqrt(upper),
    /// i.e. liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioA A sqrt price
    /// @param sqrtRatioB Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up or down
    /// @return amount0 Amount of currency0 required to cover a position of size liquidity between the two passed prices
    function getAmount0Delta(UQ64x96 sqrtRatioA, UQ64x96 sqrtRatioB, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount0)
    {
        unchecked {
            if (sqrtRatioA > sqrtRatioB) (sqrtRatioA, sqrtRatioB) = (sqrtRatioB, sqrtRatioA);

            uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
            uint256 numerator2 = (sqrtRatioB - sqrtRatioA).toUint256();

            require(sqrtRatioA > UQ64x96.wrap(0));

            return roundUp
                ? UnsafeMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioB.toUint256()), sqrtRatioA.toUint256()
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioB.toUint256()) / sqrtRatioA.toUint256();
        }
    }

    /// @notice Gets the amount1 delta between two prices
    /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioA A sqrt price
    /// @param sqrtRatioB Another sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up, or down
    /// @return amount1 Amount of currency1 required to cover a position of size liquidity between the two passed prices
    function getAmount1Delta(UQ64x96 sqrtRatioA, UQ64x96 sqrtRatioB, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioA > sqrtRatioB) (sqrtRatioA, sqrtRatioB) = (sqrtRatioB, sqrtRatioA);

        return roundUp
            ? FullMath.mulDivRoundingUp(liquidity, (sqrtRatioB - sqrtRatioA).toUint256(), FixedPoint96.ONE)
            : FullMath.mulDiv(liquidity, (sqrtRatioB - sqrtRatioA).toUint256(), FixedPoint96.ONE);
    }

    /// @notice Helper that gets signed currency0 delta
    /// @param sqrtRatioA A sqrt price
    /// @param sqrtRatioB Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount0 delta
    /// @return amount0 Amount of currency0 corresponding to the passed liquidityDelta between the two prices
    function getAmount0Delta(UQ64x96 sqrtRatioA, UQ64x96 sqrtRatioB, int128 liquidity)
        internal
        pure
        returns (int256 amount0)
    {
        unchecked {
            return liquidity < 0
                ? -getAmount0Delta(sqrtRatioA, sqrtRatioB, uint128(-liquidity), false).toInt256()
                : getAmount0Delta(sqrtRatioA, sqrtRatioB, uint128(liquidity), true).toInt256();
        }
    }

    /// @notice Helper that gets signed currency1 delta
    /// @param sqrtRatioA A sqrt price
    /// @param sqrtRatioB Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount1 delta
    /// @return amount1 Amount of currency1 corresponding to the passed liquidityDelta between the two prices
    function getAmount1Delta(UQ64x96 sqrtRatioA, UQ64x96 sqrtRatioB, int128 liquidity)
        internal
        pure
        returns (int256 amount1)
    {
        unchecked {
            return liquidity < 0
                ? -getAmount1Delta(sqrtRatioA, sqrtRatioB, uint128(-liquidity), false).toInt256()
                : getAmount1Delta(sqrtRatioA, sqrtRatioB, uint128(liquidity), true).toInt256();
        }
    }
}
