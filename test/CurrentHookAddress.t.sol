// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lockers} from "../src/libraries/Lockers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";

contract CurrentHookAddressTest is Test {
    function test_getCurrentHook() public {
        assertEq(address(Lockers.getCurrentHook()), address(0));
    }

    function test_setCurrentHook() public {
        Lockers.setCurrentHook(IHooks(address(1)));
        assertEq(address(Lockers.getCurrentHook()), address(1));
    }

    function test_setCurrentHook_TwiceDoesNotSucceed() public {
        (bool set) = Lockers.setCurrentHook(IHooks(address(1)));
        assertTrue(set);
        set = Lockers.setCurrentHook(IHooks(address(2)));
        assertFalse(set);
        assertEq(address(Lockers.getCurrentHook()), address(1));
    }

    function test_clearCurrentHook() public {
        Lockers.setCurrentHook(IHooks(address(1)));
        assertEq(address(Lockers.getCurrentHook()), address(1));
        Lockers.clearCurrentHook();
        assertEq(address(Lockers.getCurrentHook()), address(0));
    }

    function test_setCurrentHook_afterLock() public {
        Lockers.push(address(this), address(this));
        Lockers.setCurrentHook(IHooks(address(1)));
        assertEq(address(Lockers.getCurrentHook()), address(1));
    }

    function test_setCurrentHook_beforeAndAfterLock() public {
        Lockers.push(address(this), address(this));
        Lockers.setCurrentHook(IHooks(address(2)));
        assertEq(address(Lockers.getCurrentHook()), address(2));
        Lockers.push(address(1), address(1));
        assertEq(address(Lockers.getCurrentHook()), address(0));
    }
}
