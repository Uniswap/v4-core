pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FullMathTest} from "../../contracts/test/FullMathTest.sol";

contract FullMathTestTest is Test {
    uint256 constant Q128 = 1 << 128;
    uint256 constant MAX_UINT256 = type(uint256).max;

    FullMathTest fullMath;

    function setUp() public {
        fullMath = new FullMathTest();
    }

    function test_mulDiv_revertsIfDemoninatorIs0() public {
        vm.expectRevert();
        fullMath.mulDiv(Q128, 5, 0);
    }

    function test_mulDiv_revertsIfDemoninatorIs0AndNumberatorOverflows() public {
        vm.expectRevert();
        fullMath.mulDiv(Q128, Q128, 0);
    }

    function test_mulDiv_revertsIfOuptutOverflowsUint256() public {
        vm.expectRevert();
        fullMath.mulDiv(Q128, Q128, 1);
    }

    function test_mulDiv_revertsOnOverFlowAllMaxInputs() public {
        vm.expectRevert();
        fullMath.mulDiv(MAX_UINT256, MAX_UINT256, MAX_UINT256 - 1);
    }

    function test_mulDiv_validAllMaxInputs() public {
      assertEq(fullMath.mulDiv(MAX_UINT256, MAX_UINT256, MAX_UINT256), MAX_UINT256);
    }

    function test_mulDiv_accurateWithoutPhantomOverflow() public {
      assertEq(fullMath.mulDiv(Q128, 50 * Q128 / 100, 150 * Q128 / 100), Q128 / 3);
    }

    function test_mulDiv_accurateWithPhantomOverflow() public {
      assertEq(fullMath.mulDiv(Q128, 35 * Q128, 8 * Q128), 4375 * Q128 / 1000);
    }

    function test_mulDiv_accurateWithPhantomOverflowAndRepeatingDecimals() public {
      assertEq(fullMath.mulDiv(Q128, 1000 * Q128, 3000 * Q128), Q128 / 3);
    }

}
