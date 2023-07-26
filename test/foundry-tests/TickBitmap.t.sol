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
    // #flipTick

    function test_flipTick_flipsOnlyTheSpecifiedTick() public {
        tickBitmap.flipTick(-230);

        assertEq(tickBitmap.isInitialized(-230), true);
        assertEq(tickBitmap.isInitialized(-231), false);
        assertEq(tickBitmap.isInitialized(-229), false);
        assertEq(tickBitmap.isInitialized(-230 + 256), false);
        assertEq(tickBitmap.isInitialized(-230 - 256), false);

        tickBitmap.flipTick(-230);
        assertEq(tickBitmap.isInitialized(-230), false);
        assertEq(tickBitmap.isInitialized(-231), false);
        assertEq(tickBitmap.isInitialized(-229), false);
        assertEq(tickBitmap.isInitialized(-230 + 256), false);
        assertEq(tickBitmap.isInitialized(-230 - 256), false);

        assertEq(tickBitmap.isInitialized(1), false);
    }

    function test_flipTick_revertsOnlyItself() public {
        tickBitmap.flipTick(-230);
        tickBitmap.flipTick(-259);
        tickBitmap.flipTick(-229);
        tickBitmap.flipTick(500);
        tickBitmap.flipTick(-259);
        tickBitmap.flipTick(-229);
        tickBitmap.flipTick(-259);

        assertEq(tickBitmap.isInitialized(-259), true);
        assertEq(tickBitmap.isInitialized(-229), false);
    }

    function test_flipTick_gasCostOfFlippingFirstTickInWordToInitialized() public {
        uint256 gasCost = tickBitmap.getGasCostOfFlipTick(1);

        assertGt(gasCost, 0);
    }

    function test_flipTick_gasCostOfFlippingSecondTickInWordToInitialized() public {
        tickBitmap.flipTick(0);
        uint256 gasCost = tickBitmap.getGasCostOfFlipTick(1);

        assertGt(gasCost, 0);
    }

    function test_flipTick_gasCostOfFlippingATickThatResultsInDeletingAWord() public {
        tickBitmap.flipTick(0);
        uint256 gasCost = tickBitmap.getGasCostOfFlipTick(0);

        assertGt(gasCost, 0);
    }
}
