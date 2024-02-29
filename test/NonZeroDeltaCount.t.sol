// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NonZeroDeltaCount} from "../src/libraries/NonZeroDeltaCount.sol";

contract NonZeroDeltaCountTest is Test {
    address constant ADDRESS_AS = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address constant ADDRESS_BS = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    function test_incrementNonzeroDeltaCount() public {
        NonZeroDeltaCount.increment();
        assertEq(NonZeroDeltaCount.read(), 1);
    }

    function test_decrementNonzeroDeltaCount() public {
        NonZeroDeltaCount.increment();
        NonZeroDeltaCount.decrement();
        assertEq(NonZeroDeltaCount.read(), 0);
    }

    // Reading from right to left. Bit of 0: call increase. Bit of 1: call decrease.
    // The library allows over over/underflow so we dont check for that here
    function test_fuzz_nonZeroDeltaCount(uint256 instructions) public {
        uint256 expectedCount;
        for (uint256 i = 0; i < 256; i++) {
            if ((instructions & (1 << i)) == 0) {
                NonZeroDeltaCount.increment();
                unchecked {
                    expectedCount++;
                }
            } else {
                NonZeroDeltaCount.decrement();
                unchecked {
                    expectedCount--;
                }
            }
            assertEq(NonZeroDeltaCount.read(), expectedCount);
        }
    }
}
