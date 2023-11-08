// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {NoDelegateCallTest} from "../src/test/NoDelegateCallTest.sol";

contract TestDelegateCall is Test, GasSnapshot {
    error DelegateCallNotAllowed();

    NoDelegateCallTest noDelegateCallTest;

    function setUp() public {
        noDelegateCallTest = new NoDelegateCallTest();
    }

    function testGasOverhead() public {
        snap(
            "NoDelegateCallOverhead",
            noDelegateCallTest.getGasCostOfCannotBeDelegateCalled()
                - noDelegateCallTest.getGasCostOfCanBeDelegateCalled()
        );
    }

    function testDelegateCallNoModifier() public {
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.canBeDelegateCalled.selector));
        assertTrue(success);
    }

    function testDelegateCallWithModifier() public {
        vm.expectRevert(DelegateCallNotAllowed.selector);
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.cannotBeDelegateCalled.selector));
        // note vm.expectRevert inverts success, so a true result here means it reverted
        assertTrue(success);
    }

    function testCanCallIntoPrivateMethodWithModifier() public view {
        noDelegateCallTest.callsIntoNoDelegateCallFunction();
    }

    function testCannotDelegateCallPrivateMethodWithModifier() public {
        vm.expectRevert(DelegateCallNotAllowed.selector);
        (bool success,) = address(noDelegateCallTest).delegatecall(
            abi.encode(noDelegateCallTest.callsIntoNoDelegateCallFunction.selector)
        );
        // note vm.expectRevert inverts success, so a true result here means it reverted
        assertTrue(success);
    }
}
