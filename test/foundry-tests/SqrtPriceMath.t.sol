// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SqrtPriceMathTest} from "../../contracts/test/SqrtPriceMathTest.sol";
import {Constants} from "./utils/Constants.sol";

contract SqrtPriceMathTestTest is Test {
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint128 constant MAX_UINT128 = type(uint128).max;

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
        uint128 liquidity = MAX_UINT128;
        uint256 maxAmountNoOverflow = MAX_UINT256 - MAX_UINT128 << 96 / sqrtP;

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

        uint160 sqrtQ = sqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, 1, MAX_UINT256 / 2, true);

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
}
