// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickBitmapTest} from "../../contracts/test/TickBitmapTest.sol";

contract TickBitmapTestTest is Test {
    TickBitmapTest tickBitmap;

    function setUp() public {
        tickBitmap = new TickBitmapTest();
    }

    // #isInitialized

    function test_isInitialized_isFalseAtFirst() public {
        assertEq(tickBitmap.isInitialized(1), false);
    }

    function test_isInitialized_isFlippedByFlapTick() public {
        tickBitmap.flipTick(1);

        assertEq(tickBitmap.isInitialized(1), true);
    }

    function test_isInitialized_isFlippedBackByFlapTick() public {
        tickBitmap.flipTick(1);
        tickBitmap.flipTick(1);

        assertEq(tickBitmap.isInitialized(1), false);
    }

    function test_isInitialized_isNotChangedByAnotherFlipToADifferentTick() public {
        tickBitmap.flipTick(2);

        assertEq(tickBitmap.isInitialized(1), false);
    }

    function test_isInitialized_isNotChangedByAnotherFlipToADifferentTickOnAnotherWord() public {
        tickBitmap.flipTick(1 + 256);

        assertEq(tickBitmap.isInitialized(257), true);
        assertEq(tickBitmap.isInitialized(1), false);
    }
}
