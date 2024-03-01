// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Locker} from "../src/libraries/Locker.sol";

contract LockerTest is Test {
    address constant ADDRESS_AS = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address constant ADDRESS_BS = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    function test_fuzz_lock() public {
        assertFalse(Locker.isLocked());

        Locker.lock();

        assertTrue(Locker.isLocked());

        Locker.unlock();

        assertFalse(Locker.isLocked());
    }
}
