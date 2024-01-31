// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Locker} from "../src/libraries/Locker.sol";

contract LockerTest is Test {
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
}
