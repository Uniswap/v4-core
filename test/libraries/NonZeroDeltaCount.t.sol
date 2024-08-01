// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NonzeroDeltaCount} from "../../src/libraries/NonzeroDeltaCount.sol";

contract NonzeroDeltaCountTest is Test {
    function test_incrementNonzeroDeltaCount() public {
        assertEq(NonzeroDeltaCount.read(), 0);
        NonzeroDeltaCount.increment();
        assertEq(NonzeroDeltaCount.read(), 1);
    }

    function test_decrementNonzeroDeltaCount() public {
        assertEq(NonzeroDeltaCount.read(), 0);
        NonzeroDeltaCount.increment();
        assertEq(NonzeroDeltaCount.read(), 1);
        NonzeroDeltaCount.decrement();
        assertEq(NonzeroDeltaCount.read(), 0);
    }

    // Reading from right to left. Bit of 0: call increase. Bit of 1: call decrease.
    // The library allows over over/underflow so we dont check for that here
    function test_fuzz_nonzeroDeltaCount(uint256 instructions) public {
        assertEq(NonzeroDeltaCount.read(), 0);
        uint256 expectedCount;
        for (uint256 i = 0; i < 256; i++) {
            if ((instructions & (1 << i)) == 0) {
                NonzeroDeltaCount.increment();
                unchecked {
                    expectedCount++;
                }
            } else {
                NonzeroDeltaCount.decrement();
                unchecked {
                    expectedCount--;
                }
            }
            assertEq(NonzeroDeltaCount.read(), expectedCount);
        }
    }

    function test_nonzeroDeltaCountSlot() public pure {
        assertEq(bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1), NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT);
    }
}
