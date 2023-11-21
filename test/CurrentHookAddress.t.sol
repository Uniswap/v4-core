// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lockers} from "../src/libraries/Lockers.sol";

contract CurrentHookAddressTest is Test {
    function test_getCurrentHook() public {
        assertEq(Lockers.getCurrentHook(), address(0));
    }

    function test_setCurrentHook() public {
        Lockers.setCurrentHook(address(1));
        assertEq(Lockers.getCurrentHook(), address(1));
    }

    function test_setCurrentHook_TwiceDoesNotSucceed() public {
        Lockers.setCurrentHook(address(1));
        Lockers.setCurrentHook(address(2));

        assertEq(Lockers.getCurrentHook(), address(1));
    }

    function test_clearCurrentHook() public {
        Lockers.setCurrentHook(address(1));
        assertEq(Lockers.getCurrentHook(), address(1));
        Lockers.clearCurrentHook();
        assertEq(Lockers.getCurrentHook(), address(0));
    }

    function test_setCurrentHook_afterLock() public {
        Lockers.push(address(this));
        Lockers.setCurrentHook(address(1));
        assertEq(Lockers.getCurrentHook(), address(1));
    }

    function test_setCurrentHook_beforeLock() public {
        Lockers.push(address(this));
        Lockers.setCurrentHook(address(2));
        assertEq(Lockers.getCurrentHook(), address(2));
        Lockers.push(address(1));
        assertEq(Lockers.getCurrentHook(), address(0));
    }
}
