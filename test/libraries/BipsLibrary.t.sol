// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BipsLibrary} from "../../src/libraries/BipsLibrary.sol";

contract BipsLibraryTest is Test {
    using BipsLibrary for uint256;

    // The block gas limit set in foundry config is 300_000_000 (300M) for testing purposes
    uint256 BLOCK_GAS_LIMIT;

    function setUp() public {
        BLOCK_GAS_LIMIT = block.gaslimit;
    }

    function test_fuzz_calculatePortion(uint256 amount, uint256 bips) public {
        amount = bound(amount, 0, uint256(type(uint128).max));
        if (bips > BipsLibrary.BPS_DENOMINATOR) {
            vm.expectRevert(BipsLibrary.InvalidBips.selector);
            amount.calculatePortion(bips);
        } else {
            assertEq(amount.calculatePortion(bips), amount * bips / BipsLibrary.BPS_DENOMINATOR);
        }
    }

    function test_fuzz_gasLimit(uint256 bips) public {
        if (bips > BipsLibrary.BPS_DENOMINATOR) {
            vm.expectRevert(BipsLibrary.InvalidBips.selector);
            block.gaslimit.calculatePortion(bips);
        } else {
            assertEq(block.gaslimit.calculatePortion(bips), BLOCK_GAS_LIMIT * bips / BipsLibrary.BPS_DENOMINATOR);
        }
    }

    function test_gasLimit_100_percent() public view {
        assertEq(block.gaslimit, block.gaslimit.calculatePortion(10_000));
    }

    function test_gasLimit_1_percent() public view {
        // 100 bps = 1%
        // 1% of 30M is 300K
        assertEq(BLOCK_GAS_LIMIT / 100, block.gaslimit.calculatePortion(100));
    }

    function test_gasLimit_1BP() public view {
        // 1bp is 0.01%
        // 0.01% of 30M is 300
        assertEq(BLOCK_GAS_LIMIT / 10000, block.gaslimit.calculatePortion(1));
    }
}
