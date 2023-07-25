// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SqrtPriceMathTest} from "../../contracts/test/SqrtPriceMathTest.sol";
import {Constants} from "./utils/Constants.sol";

contract SqrtPriceMathTestTest is Test {
    SqrtPriceMathTest sqrtPriceMath;

    function setUp() public {
        sqrtPriceMath = new SqrtPriceMathTest();
    }

    function expandTo18Decimals(uint256 a) internal pure returns (uint256) {
        uint256 multiplier = 10 ** 18;
        return a * multiplier;
    }

    function test_getNextSqrtPriceFromInput_revertsIfPriceIsZero() public {
        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromInput(0, 0, expandTo18Decimals(1) / 10, false);
    }

    function test_getNextSqrtPriceFromInput_revertsIfLiquidityIsZero() public {
        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromInput(1, 0, expandTo18Decimals(1) / 10, true);
    }

    function test_getNextSqrtPriceFromInput_revertsIfInputAmountOverflowsThePrice() public {
        uint160 price = 2 ** 160 - 1;
        uint128 liquidity = 1024;
        uint256 amountIn = 1024;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromInput(price, liquidity, amountIn, false);
    }

    function test_getNextSqrtPriceFromInput_anyInputAmountCannotUnderflowThePrice() public {
        uint160 price = 1;
        uint128 liquidity = 1;
        uint256 amountIn = 2 ** 255;

        assertEq(sqrtPriceMath.getNextSqrtPriceFromInput(price, liquidity, amountIn, true), 1);
    }

    function test_getNextSqrtPriceFromInput_returnsInputPriceIfAmountInIsZeroAndZeroForOneEqualsTrue() public {
        uint160 price = Constants.SQRT_RATIO_1_1;
        uint128 liquidity = 1;

        assertEq(sqrtPriceMath.getNextSqrtPriceFromInput(price, liquidity, 0, true), price);
    }

    function test_getNextSqrtPriceFromInput_returnsInputPriceIfAmountInIsZeroAndZeroForOneEqualsFalse() public {
        uint160 price = Constants.SQRT_RATIO_1_1;
        uint128 liquidity = 1;

        assertEq(sqrtPriceMath.getNextSqrtPriceFromInput(price, liquidity, 0, false), price);
    }

    function test_getNextSqrtPriceFromInput_returnsTheMinimumPriceForMaxInputs() public {
        uint160 sqrtP = 2 ** 160 - 1;
        uint128 liquidity = Constants.MAX_UINT128;
        uint256 maxAmountNoOverflow = Constants.MAX_UINT256 - Constants.MAX_UINT128 << 96 / sqrtP;

        assertEq(sqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, maxAmountNoOverflow, true), 1);
    }

    function test_getNextSqrtPriceFromInput_inputAmountOf0_1Currency1() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, false
        );

        assertEq(sqrtQ, 87150978765690771352898345369);
    }

    function test_getNextSqrtPriceFromInput_inputAmountOf0_1Currency0() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, true
        );

        assertEq(sqrtQ, 72025602285694852357767227579);
    }

    function test_getNextSqrtPriceFromInput_amountInGreaterThanType_uint96_maxAndZeroForOneEqualsTrue() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, uint128(expandTo18Decimals(10)), 2 ** 100, true);

        // perfect answer:
        // https://www.wolframalpha.com/input/?i=624999999995069620+-+%28%281e19+*+1+%2F+%281e19+%2B+2%5E100+*+1%29%29+*+2%5E96%29
        assertEq(sqrtQ, 624999999995069620);
    }

    function test_getNextSqrtPriceFromInput_canReturn1WithEnoughAmountInAndZeroForOneEqualsTrue() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, 1, Constants.MAX_UINT256 / 2, true);

        assertEq(sqrtQ, 1);
    }

    function test_getNextSqrtPriceFromInput_zeroForOneEqualsTrueGas() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 gasCost = sqrtPriceMath.getGasCostOfGetNextSqrtPriceFromInput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, true
        );

        assertGt(gasCost, 0);
    }

    function test_getNextSqrtPriceFromInput_zeroForOneEqualsFalseGas() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 gasCost = sqrtPriceMath.getGasCostOfGetNextSqrtPriceFromInput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, false
        );

        assertGt(gasCost, 0);
    }

    // #getNextSqrtPriceFromOutput

    function test_getNextSqrtPriceFromOutput_revertsIfPriceIsZero() public {
        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(0, 0, expandTo18Decimals(1) / 10, false);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfLiquidityIsZero() public {
        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(1, 0, expandTo18Decimals(1) / 10, true);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfOutputAmountIsExactlyTheVirtualReservesOfCurrency0() public {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 4;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, false);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfOutputAmountIsGreaterThanTheVirtualReservesOfCurrency0() public {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 5;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, false);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfOutputAmountIsGreaterThanTheVirtualReservesOfCurrency1() public {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 262145;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, true);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfOutputAmountIsExactlyTheVirtualReservesOfCurrency1() public {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 262144;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, true);
    }

    function test_getNextSqrtPriceFromOutput_succeedsIfOutputAmountIsJustLessThanTheVirtualReservesOfCurrency1()
        public
    {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 262143;

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, true);

        assertEq(sqrtQ, 77371252455336267181195264);
    }

    function test_getNextSqrtPriceFromOutput_puzzlingEchidnaTest() public {
        uint160 price = 20282409603651670423947251286016;
        uint128 liquidity = 1024;
        uint256 amountOut = 4;

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(price, liquidity, amountOut, false);
    }

    function test_getNextSqrtPriceFromOutput_returnsInputPriceIfAmountInIsZeroAndZeroForOneEqualsTrue() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, uint128(expandTo18Decimals(1) / 10), 0, true);

        assertEq(sqrtP, sqrtQ);
    }

    function test_getNextSqrtPriceFromOutput_returnsInputPriceIfAmountInIsZeroAndZeroForOneEqualsFalse() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, uint128(expandTo18Decimals(1) / 10), 0, false);

        assertEq(sqrtP, sqrtQ);
    }

    function test_getNextSqrtPriceFromOutput_outputAmountOf0_1Currency1() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromOutput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, false
        );

        assertEq(sqrtQ, 88031291682515930659493278152);
    }

    function test_getNextSqrtPriceFromOutput_outputAmountOf0_1Currency0() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromOutput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, true
        );

        assertEq(sqrtQ, 71305346262837903834189555302);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfAmountOutIsImpossibleInZeroForOneDirection() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, 1, Constants.MAX_UINT256, true);
    }

    function test_getNextSqrtPriceFromOutput_revertsIfAmountOutIsImpossibleInOneForZeroDirection() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        vm.expectRevert();
        sqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, 1, Constants.MAX_UINT256, false);
    }

    function test_getNextSqrtPriceFromOutput_zeroForOneEqualsTrueGas() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 gasCost = sqrtPriceMath.getGasCostOfGetNextSqrtPriceFromOutput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, true
        );

        assertGt(gasCost, 0);
    }

    function test_getNextSqrtPriceFromOutput_zeroForOneEqualsFalseGas() public {
        uint160 sqrtP = Constants.SQRT_RATIO_1_1; // sqrtP = encodeSqrtPriceX96(1, 1)

        uint256 gasCost = sqrtPriceMath.getGasCostOfGetNextSqrtPriceFromOutput(
            sqrtP, uint128(expandTo18Decimals(1)), expandTo18Decimals(1) / 10, false
        );

        assertGt(gasCost, 0);
    }

    // #getAmount0Delta

    function test_getAmount0Delta_returns0IfLiquidityIs0() public {
        uint256 amount0 = sqrtPriceMath.getAmount0Delta(Constants.SQRT_RATIO_1_1, Constants.SQRT_RATIO_2_1, 0, true);

        assertEq(amount0, 0);
    }

    function test_getAmount0Delta_returns0IfPricesAreEqual() public {
        uint256 amount0 = sqrtPriceMath.getAmount0Delta(Constants.SQRT_RATIO_1_1, Constants.SQRT_RATIO_1_1, 0, true);

        assertEq(amount0, 0);
    }

    function test_getAmount0Delta_returns0_1Amount1ForPriceOf1To1_21() public {
        uint256 amount0 = sqrtPriceMath.getAmount0Delta(
            Constants.SQRT_RATIO_1_1, Constants.SQRT_RATIO_121_100, uint128(expandTo18Decimals(1)), true
        );

        assertEq(amount0, 90909090909090910);

        uint256 amount0RoundedDown = sqrtPriceMath.getAmount0Delta(
            Constants.SQRT_RATIO_1_1, Constants.SQRT_RATIO_121_100, uint128(expandTo18Decimals(1)), false
        );

        assertEq(amount0RoundedDown, amount0 - 1);
    }

    function test_getAmount0Delta_worksForPricesThatOverflow() public {
        // sqrtP_1 = encodeSqrtPriceX96(2^90, 1)
        uint160 sqrtP_1 = 2787593149816327892691964784081045188247552;
        // sqrtP_2 = encodeSqrtPriceX96(2^96, 1)
        uint160 sqrtP_2 = 22300745198530623141535718272648361505980416;

        uint256 amount0Up = sqrtPriceMath.getAmount0Delta(sqrtP_1, sqrtP_2, uint128(expandTo18Decimals(1)), true);

        uint256 amount0Down = sqrtPriceMath.getAmount0Delta(sqrtP_1, sqrtP_2, uint128(expandTo18Decimals(1)), false);

        assertEq(amount0Up, amount0Down + 1);
    }

    function test_getAmount0Delta_gasCostForAmount0WhereRoundUpIsTrue() public {
        uint256 gasCost = sqrtPriceMath.getGasCostOfGetAmount0Delta(
            Constants.SQRT_RATIO_121_100, Constants.SQRT_RATIO_1_1, uint128(expandTo18Decimals(1)), true
        );

        assertGt(gasCost, 0);
    }

    function test_getAmount0Delta_gasCostForAmount0WhereRoundUpIsFalse() public {
        uint256 gasCost = sqrtPriceMath.getGasCostOfGetAmount0Delta(
            Constants.SQRT_RATIO_121_100, Constants.SQRT_RATIO_1_1, uint128(expandTo18Decimals(1)), false
        );

        assertGt(gasCost, 0);
    }
}
