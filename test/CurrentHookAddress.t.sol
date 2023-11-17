// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CurrentHookAddress} from "../src/libraries/CurrentHookAddress.sol";

contract CurrentHookAddressTest is Test {
    function test_get_currentHookAddress() public {
        assertEq(CurrentHookAddress.get(), address(0));
    }

    function test_set_currentHookAddress() public {
        CurrentHookAddress.set(address(1));
        assertEq(CurrentHookAddress.get(), address(1));
    }

    function test_set_currentHookAddressTwice() public {
        CurrentHookAddress.set(address(1));
        CurrentHookAddress.set(address(2));

        assertEq(CurrentHookAddress.get(), address(2));
    }
}
