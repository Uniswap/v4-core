// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Locker} from "../src/libraries/Locker.sol";

contract CurrentHookAddressTest is Test {
    address constant ADDRESS_AS = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address constant ADDRESS_BS = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    function test_setLockerAndCaller() public {
        assertEq(address(Locker.getLocker()), address(0));
        assertEq(address(Locker.getLockCaller()), address(0));

        Locker.setLockerAndCaller(ADDRESS_AS, ADDRESS_BS);

        assertEq(address(Locker.getLocker()), ADDRESS_AS);
        assertEq(address(Locker.getLockCaller()), ADDRESS_BS);

        // in the way this library is used in V4, this function will never be called when non-0
        Locker.setLockerAndCaller(ADDRESS_BS, ADDRESS_AS);

        assertEq(address(Locker.getLocker()), ADDRESS_BS);
        assertEq(address(Locker.getLockCaller()), ADDRESS_AS);
    }

    function test_clearLockerAndCaller() public {
        Locker.setLockerAndCaller(ADDRESS_AS, ADDRESS_BS);

        assertEq(address(Locker.getLocker()), ADDRESS_AS);
        assertEq(address(Locker.getLockCaller()), ADDRESS_BS);

        Locker.clearLockerAndCaller();

        assertEq(address(Locker.getLocker()), address(0));
        assertEq(address(Locker.getLockCaller()), address(0));
    }

    function test_isLocked() public {
        assertFalse(Locker.isLocked());

        Locker.setLockerAndCaller(ADDRESS_AS, ADDRESS_BS);

        assertTrue(Locker.isLocked());

        Locker.clearLockerAndCaller();

        assertFalse(Locker.isLocked());
    }

    function test_incrementNonzeroDeltaCount() public {
        Locker.incrementNonzeroDeltaCount();
        assertEq(Locker.nonzeroDeltaCount(), 1);
    }

    function test_decrementNonzeroDeltaCount() public {
        Locker.incrementNonzeroDeltaCount();
        Locker.decrementNonzeroDeltaCount();
        assertEq(Locker.nonzeroDeltaCount(), 0);
    }

    // Reading from right to left. Bit of 0: call increase. Bit of 1: call decrease.
    // The library allows over over/underflow so we dont check for that here
    function test_nonZeroDeltaCount_fuzz(uint256 instructions) public {
        uint256 expectedCount;
        for (uint256 i = 0; i < 256; i++) {
            if ((instructions & (1 << i)) == 0) {
                Locker.incrementNonzeroDeltaCount();
                unchecked {
                    expectedCount++;
                }
            } else {
                Locker.decrementNonzeroDeltaCount();
                unchecked {
                    expectedCount--;
                }
            }
            assertEq(Locker.nonzeroDeltaCount(), expectedCount);
        }
    }
}
