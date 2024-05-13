// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {NoDelegateCallTest} from "../src/test/NoDelegateCallTest.sol";
import {NoDelegateCall} from "../src/NoDelegateCall.sol";

contract TestDelegateCall is Test, GasSnapshot {
    NoDelegateCallTest noDelegateCallTest;

    function setUp() public {
        noDelegateCallTest = new NoDelegateCallTest();
    }

    function test_gas_noDelegateCall() public {
        snap(
            "NoDelegateCall",
            noDelegateCallTest.getGasCostOfCannotBeDelegateCalled()
                - noDelegateCallTest.getGasCostOfCanBeDelegateCalled()
        );
    }

    function test_delegateCallNoModifier() public {
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.canBeDelegateCalled.selector));
        assertTrue(success);
    }

    function test_delegateCallWithModifier_revertsWithDelegateCallNotAllowed() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        (bool success,) =
            address(noDelegateCallTest).delegatecall(abi.encode(noDelegateCallTest.cannotBeDelegateCalled.selector));
        // note vm.expectRevert inverts success, so a true result here means it reverted
        assertTrue(success);
    }

    function test_externalCallToPrivateMethodWithModifer_succeeds() public view {
        noDelegateCallTest.callsIntoNoDelegateCallFunction();
    }

    function test_delegateCallFromExternalToPrivateMethodWithModifier_revertsWithDelegateCallNotAllowed() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        (bool success,) = address(noDelegateCallTest).delegatecall(
            abi.encode(noDelegateCallTest.callsIntoNoDelegateCallFunction.selector)
        );
        // note vm.expectRevert inverts success, so a true result here means it reverted
        assertTrue(success);
    }
}
