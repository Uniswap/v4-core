// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {SqrtPriceMathTest} from "../../contracts/test/SqrtPriceMathTest.sol";
import "../../contracts/libraries/SqrtPriceMath.sol";

contract TestSqrtPriceMath is Test, GasSnapshot {
    // Wrapper contracts that expose the SqrtPriceMath library. Useful for catching reverts.
    SqrtPriceMathTest internal wrapper;
    SqrtPriceMathReference internal refWrapper;

    function setUp() public {
        wrapper = new SqrtPriceMathTest();
        refWrapper = new SqrtPriceMathReference();
    }

    /// @dev Bound a `uint160` to between `MIN_SQRT_RATIO` and `MAX_SQRT_RATIO`.
    function boundUint160(uint160 x) internal view returns (uint160) {
        return uint160(bound(x, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO));
    }

    /// @dev Get a deterministic pseudo-random number.
    function pseudoRandom(uint256 seed) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed)));
    }

    function pseudoRandomUint160(uint256 seed) internal pure returns (uint160) {
        return uint160(pseudoRandom(seed));
    }

    function pseudoRandomUint128(uint256 seed) internal pure returns (uint128) {
        return uint128(pseudoRandom(seed));
    }

    function pseudoRandomInt128(uint256 seed) internal pure returns (int128) {
        return int128(int256(pseudoRandom(seed)));
    }

    function testFuzzGetNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) external {
        sqrtPX96 = boundUint160(sqrtPX96);
        try refWrapper.getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amount, add) returns (
            uint160 expected
        ) {
            assertEq(wrapper.getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amount, add), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amount, add);
        }
    }

    function testFuzzGetNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) external {
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        sqrtPX96 = boundUint160(sqrtPX96);
        amount = bound(amount, 0, FullMath.mulDiv(type(uint160).max, liquidity, FixedPoint96.Q96));
        try refWrapper.getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amount, add) returns (
            uint160 expected
        ) {
            assertEq(wrapper.getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amount, add), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amount, add);
        }
    }

    function testFuzzGetNextSqrtPriceFromInput(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external
    {
        try refWrapper.getNextSqrtPriceFromInput(sqrtPX96, liquidity, amountIn, zeroForOne) returns (uint160 expected) {
            assertEq(wrapper.getNextSqrtPriceFromInput(sqrtPX96, liquidity, amountIn, zeroForOne), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getNextSqrtPriceFromInput(sqrtPX96, liquidity, amountIn, zeroForOne);
        }
    }

    function testFuzzGetNextSqrtPriceFromOutput(uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        external
    {
        try refWrapper.getNextSqrtPriceFromOutput(sqrtPX96, liquidity, amountOut, zeroForOne) returns (uint160 expected)
        {
            assertEq(wrapper.getNextSqrtPriceFromOutput(sqrtPX96, liquidity, amountOut, zeroForOne), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getNextSqrtPriceFromOutput(sqrtPX96, liquidity, amountOut, zeroForOne);
        }
    }

    function testFuzzGetAmount0Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity, bool roundUp)
        external
    {
        try refWrapper.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp) returns (uint256 expected) {
            assertEq(wrapper.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
        }
    }

    function testFuzzGetAmount1Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity, bool roundUp)
        external
    {
        try refWrapper.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp) returns (uint256 expected) {
            assertEq(wrapper.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
        }
    }

    function testFuzzGetAmount0DeltaSigned(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity) external {
        try refWrapper.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity) returns (int256 expected) {
            assertEq(wrapper.getAmount0DeltaSigned(sqrtRatioAX96, sqrtRatioBX96, liquidity), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getAmount0DeltaSigned(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    function testFuzzGetAmount1DeltaSigned(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity) external {
        try refWrapper.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity) returns (int256 expected) {
            assertEq(wrapper.getAmount1DeltaSigned(sqrtRatioAX96, sqrtRatioBX96, liquidity), expected);
        } catch (bytes memory) {
            vm.expectRevert();
            wrapper.getAmount1DeltaSigned(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    function testGasGetNextSqrtPriceFromInput() external view {
        for (uint256 i; i < 100; ++i) {
            try wrapper.getNextSqrtPriceFromInput(
                pseudoRandomUint160(i), pseudoRandomUint128(i ** 2), pseudoRandom(i ** 3), i % 2 == 0
            ) {} catch {}
        }
    }

    function testGasGetNextSqrtPriceFromOutput() external view {
        for (uint256 i; i < 100; ++i) {
            try wrapper.getNextSqrtPriceFromOutput(
                pseudoRandomUint160(i), pseudoRandomUint128(i ** 2), pseudoRandom(i ** 3), i % 2 == 0
            ) {} catch {}
        }
    }

    function testGasGetAmount0DeltaSigned() external view {
        for (uint256 i; i < 100; ++i) {
            try wrapper.getAmount0DeltaSigned(
                pseudoRandomUint160(i), pseudoRandomUint160(i ** 2), pseudoRandomInt128(i ** 3)
            ) {} catch {}
        }
    }

    function testGasGetAmount1DeltaSigned() external view {
        for (uint256 i; i < 100; ++i) {
            try wrapper.getAmount1DeltaSigned(
                pseudoRandomUint160(i), pseudoRandomUint160(i ** 2), pseudoRandomInt128(i ** 3)
            ) {} catch {}
        }
    }
}

/// @notice A reference implementation of the functions in SqrtPriceMath
contract SqrtPriceMathReference {
    using SafeCast for uint256;

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
        public
        pure
        returns (uint160)
    {
        // we short circuit amount == 0 because the result is otherwise not guaranteed to equal the input price
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            unchecked {
                uint256 product;
                if ((product = amount * sqrtPX96) / amount == sqrtPX96) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        // always fits in 160 bits
                        return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
                    }
                }
            }
            // denominator is checked for overflow
            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96) + amount));
        } else {
            unchecked {
                uint256 product;
                // if the product overflows, we know the denominator underflows
                // in addition, we must check that the denominator does not underflow
                require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
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
        public
        pure
        returns (uint160)
    {
        // if we're adding (subtracting), rounding down requires rounding the quotient down (up)
        // in both cases, avoid a mulDiv for most inputs
        if (add) {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? (amount << FixedPoint96.RESOLUTION) / liquidity
                    : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
            );

            return (uint256(sqrtPX96) + quotient).toUint160();
        } else {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
                    : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
            );

            require(sqrtPX96 > quotient);
            // always fits 160 bits
            return uint160(sqrtPX96 - quotient);
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
        public
        pure
        returns (uint160 sqrtQX96)
    {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

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
        public
        pure
        returns (uint160 sqrtQX96)
    {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // round to make sure that we pass the target price
        return zeroForOne
            ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
            : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
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
        public
        pure
        returns (uint256 amount0)
    {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
            uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

            require(sqrtRatioAX96 > 0);

            return roundUp
                ? UnsafeMath.divRoundingUp(FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96), sqrtRatioAX96)
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
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
        public
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return roundUp
            ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
            : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice Helper that gets signed currency0 delta
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount0 delta
    /// @return amount0 Amount of currency0 corresponding to the passed liquidityDelta between the two prices
    function getAmount0Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        public
        pure
        returns (int256 amount0)
    {
        unchecked {
            return liquidity < 0
                ? -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
        }
    }

    /// @notice Helper that gets signed currency1 delta
    /// @param sqrtRatioAX96 A sqrt price
    /// @param sqrtRatioBX96 Another sqrt price
    /// @param liquidity The change in liquidity for which to compute the amount1 delta
    /// @return amount1 Amount of currency1 corresponding to the passed liquidityDelta between the two prices
    function getAmount1Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        public
        pure
        returns (int256 amount1)
    {
        unchecked {
            return liquidity < 0
                ? -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
        }
    }
}
