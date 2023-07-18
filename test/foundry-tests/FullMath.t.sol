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

    function test_mulDivRoundingUp_revertsIfDenominatorIs0() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(Q128, 5, 0);
    }

    function test_mulDivRoundingUp_revertsIfDemoninatorIs0AndNumberatorOverflows() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(Q128, Q128, 0);
    }

    function test_mulDivRoundingUp_revertsIfOuptutOverflowsUint256() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(Q128, Q128, 1);
    }

    function test_mulDivRoundingUp_revertsOnOverFlowAllMaxInputs() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(MAX_UINT256, MAX_UINT256, MAX_UINT256 - 1);
    }

    function test_mulDivRoundingUp_revertsIfMulDivOverflows256BitsAfterRoundingUp() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(535006138814359, 432862656469423142931042426214547535783388063929571229938474969, 2);
    }

    function test_mulDivRoundingUp_revertsIfMulDivOverflows256BitsAfterRoundingUpCase2() public {
        vm.expectRevert();
        fullMath.mulDivRoundingUp(
            115792089237316195423570985008687907853269984659341747863450311749907997002549,
            115792089237316195423570985008687907853269984659341747863450311749907997002550,
            115792089237316195423570985008687907853269984653042931687443039491902864365164
        );
    }

    function test_mulDivRoundingUp_validAllMaxInputs() public {
        assertEq(fullMath.mulDivRoundingUp(MAX_UINT256, MAX_UINT256, MAX_UINT256), MAX_UINT256);
    }

    function test_mulDivRoundingUp_accurateWithoutPhantomOverflow() public {
        assertEq(fullMath.mulDivRoundingUp(Q128, 50 * Q128 / 100, 150 * Q128 / 100), Q128 / 3 + 1);
    }

    function test_mulDivRoundingUp_accurateWithPhantomOverflow() public {
        assertEq(fullMath.mulDivRoundingUp(Q128, 35 * Q128, 8 * Q128), 4375 * Q128 / 1000);
    }

    function test_mulDivRoundingUp_accurateWithPhantomOverflowAndRepeatingDecimal() public {
        assertEq(fullMath.mulDivRoundingUp(Q128, 1000 * Q128, 3000 * Q128), Q128 / 3 + 1);
    }
}
