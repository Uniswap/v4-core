pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickMathTest} from "../../contracts/test/TickMathTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";

contract TickMathTestTest is Test {
    TickMathTest ticMath;

    function setUp() public {
        tickMath = new TickMathTest();
    }

    function test_getSqrtRatioAtTick_throwsForTooLow() {
        vm.expectRevert(TickMath.InvalidTick.selector);
        tickMath.getSqrtRatioAtTick(tickMath.MIN_TICK - 1);
    }
}
