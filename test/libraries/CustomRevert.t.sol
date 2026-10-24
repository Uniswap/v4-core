// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CustomRevert} from "../../src/libraries/CustomRevert.sol";

/// @notice Harness contract to expose internal CustomRevert functions for testing
contract CustomRevertHarness {
    using CustomRevert for bytes4;

    error SimpleError();
    error AddressError(address);
    error Int24Error(int24);
    error Uint160Error(uint160);
    error TwoInt24Error(int24, int24);
    error TwoUint160Error(uint160, uint160);
    error TwoAddressError(address, address);

    function revertWithNoArgs() external pure {
        SimpleError.selector.revertWith();
    }

    function revertWithAddress(address addr) external pure {
        AddressError.selector.revertWith(addr);
    }

    function revertWithInt24(int24 value) external pure {
        Int24Error.selector.revertWith(value);
    }

    function revertWithUint160(uint160 value) external pure {
        Uint160Error.selector.revertWith(value);
    }

    function revertWithTwoInt24(int24 value1, int24 value2) external pure {
        TwoInt24Error.selector.revertWith(value1, value2);
    }

    function revertWithTwoUint160(uint160 value1, uint160 value2) external pure {
        TwoUint160Error.selector.revertWith(value1, value2);
    }

    function revertWithTwoAddresses(address addr1, address addr2) external pure {
        TwoAddressError.selector.revertWith(addr1, addr2);
    }

    function callAndBubbleUp(address target, bytes calldata data, bytes4 additionalContext) external view {
        (bool success,) = target.staticcall(data);
        if (!success) {
            CustomRevert.bubbleUpAndRevertWith(target, bytes4(data[:4]), additionalContext);
        }
    }
}

/// @notice Helper contract that always reverts
contract AlwaysReverts {
    error InnerError(uint256 value);

    function failWithInnerError(uint256 val) external pure {
        revert InnerError(val);
    }
}

contract CustomRevertTest is Test {
    CustomRevertHarness harness;
    AlwaysReverts reverter;

    function setUp() public {
        harness = new CustomRevertHarness();
        reverter = new AlwaysReverts();
    }

    function test_revertWith_noArgs() public {
        vm.expectRevert(CustomRevertHarness.SimpleError.selector);
        harness.revertWithNoArgs();
    }

    function test_revertWith_address() public {
        address addr = address(0xBEEF);
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.AddressError.selector, addr));
        harness.revertWithAddress(addr);
    }

    function test_revertWith_addressZero() public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.AddressError.selector, address(0)));
        harness.revertWithAddress(address(0));
    }

    function test_fuzz_revertWith_address(address addr) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.AddressError.selector, addr));
        harness.revertWithAddress(addr);
    }

    function test_revertWith_int24_positive() public {
        int24 val = 8388607; // max int24
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Int24Error.selector, val));
        harness.revertWithInt24(val);
    }

    function test_revertWith_int24_negative() public {
        int24 val = -8388608; // min int24
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Int24Error.selector, val));
        harness.revertWithInt24(val);
    }

    function test_revertWith_int24_zero() public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Int24Error.selector, int24(0)));
        harness.revertWithInt24(int24(0));
    }

    function test_fuzz_revertWith_int24(int24 value) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Int24Error.selector, value));
        harness.revertWithInt24(value);
    }

    function test_revertWith_uint160() public {
        uint160 val = type(uint160).max;
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Uint160Error.selector, val));
        harness.revertWithUint160(val);
    }

    function test_fuzz_revertWith_uint160(uint160 value) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.Uint160Error.selector, value));
        harness.revertWithUint160(value);
    }

    function test_revertWith_twoInt24() public {
        int24 v1 = 100;
        int24 v2 = -200;
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoInt24Error.selector, v1, v2));
        harness.revertWithTwoInt24(v1, v2);
    }

    function test_fuzz_revertWith_twoInt24(int24 v1, int24 v2) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoInt24Error.selector, v1, v2));
        harness.revertWithTwoInt24(v1, v2);
    }

    function test_revertWith_twoUint160() public {
        uint160 v1 = 1;
        uint160 v2 = type(uint160).max;
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoUint160Error.selector, v1, v2));
        harness.revertWithTwoUint160(v1, v2);
    }

    function test_fuzz_revertWith_twoUint160(uint160 v1, uint160 v2) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoUint160Error.selector, v1, v2));
        harness.revertWithTwoUint160(v1, v2);
    }

    function test_revertWith_twoAddresses() public {
        address a1 = address(0x1);
        address a2 = address(0x2);
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoAddressError.selector, a1, a2));
        harness.revertWithTwoAddresses(a1, a2);
    }

    function test_fuzz_revertWith_twoAddresses(address a1, address a2) public {
        vm.expectRevert(abi.encodeWithSelector(CustomRevertHarness.TwoAddressError.selector, a1, a2));
        harness.revertWithTwoAddresses(a1, a2);
    }

    function test_bubbleUpAndRevertWith() public {
        bytes memory callData = abi.encodeWithSelector(AlwaysReverts.failWithInnerError.selector, uint256(42));
        bytes4 context = bytes4(0xffffffff);

        vm.expectRevert();
        harness.callAndBubbleUp(address(reverter), callData, context);
    }

    function test_bubbleUpAndRevertWith_encodesWrappedError() public {
        bytes memory innerCallData = abi.encodeWithSelector(AlwaysReverts.failWithInnerError.selector, uint256(42));
        bytes4 context = bytes4(0xaabbccdd);

        // Get the inner revert data
        (bool success, bytes memory innerRevertData) =
            address(reverter).staticcall(innerCallData);
        assertFalse(success);

        // Expect WrappedError with correct parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(reverter),
                AlwaysReverts.failWithInnerError.selector,
                innerRevertData,
                abi.encodePacked(context)
            )
        );
        harness.callAndBubbleUp(address(reverter), innerCallData, context);
    }
}
