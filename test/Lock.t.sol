// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lock} from "../src/libraries/Lock.sol";

contract LockTest is Test {
    function test_lock() public {
        assertFalse(Lock.isLocked());

        Lock.lock();

        assertTrue(Lock.isLocked());

        Lock.unlock();

        assertFalse(Lock.isLocked());
    }
}
