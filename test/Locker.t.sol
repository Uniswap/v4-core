// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Locker} from "../src/libraries/Locker.sol";

contract LockerTest is Test {
    address constant ADDRESS_AS = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address constant ADDRESS_BS = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    function test_fuzz_setLocker(address locker) public {
        assertEq(address(Locker.getLocker()), address(0));

        if (locker == address(0)) {
            vm.expectRevert(Locker.InvalidLocker.selector);
            Locker.setLocker(locker);
        } else {
            Locker.setLocker(locker);
            assertEq(address(Locker.getLocker()), locker);
        }
    }

    function test_fuzz_clearLocker(address locker) public {
        vm.assume(locker != address(0));
        Locker.setLocker(locker);

        assertEq(address(Locker.getLocker()), locker);

        Locker.clearLocker();

        assertEq(address(Locker.getLocker()), address(0));
    }

    function test_fuzz_isLocked(address locker) public {
        vm.assume(locker != address(0));
        assertFalse(Locker.isLocked());

        Locker.setLocker(locker);

        assertTrue(Locker.isLocked());

        Locker.clearLocker();

        assertFalse(Locker.isLocked());
    }
}
