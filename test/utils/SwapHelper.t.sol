// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {MockHooks} from "../../src/test/MockHooks.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Deployers} from "./Deployers.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {Constants} from "../utils/Constants.sol";

/// @notice Testing Deployers.swap() and Deployers.swapNativeInput()
contract SwapHelperTest is Test, Deployers {
    using Hooks for IHooks;

    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(Constants.ALL_HOOKS, address(impl).code);
        mockHooks = MockHooks(Constants.ALL_HOOKS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    // --- Deployers.swap() tests --- //
    function test_swap_helper_zeroForOne_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertEq(result.amount0(), amountSpecified);
    }

    function test_swap_helper_zeroForOne_exactOutput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertEq(result.amount1(), amountSpecified);
    }

    function test_swap_helper_oneForZero_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(key, false, amountSpecified, ZERO_BYTES);
        assertEq(result.amount1(), amountSpecified);
    }

    function test_swap_helper_oneForZero_exactOutput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(key, false, amountSpecified, ZERO_BYTES);
        assertEq(result.amount0(), amountSpecified);
    }

    function test_swap_helper_native_zeroForOne_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(nativeKey, true, amountSpecified, ZERO_BYTES);
        assertEq(result.amount0(), amountSpecified);
    }

    function test_swap_helper_native_zeroForOne_exactOutput() public {
        int256 amountSpecified = 100;
        vm.expectRevert();
        swap(nativeKey, true, amountSpecified, ZERO_BYTES);
    }

    function test_swap_helper_native_oneForZero_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(nativeKey, false, amountSpecified, ZERO_BYTES);
        assertEq(result.amount1(), amountSpecified);
    }

    function test_swap_helper_native_oneForZero_exactOutput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(nativeKey, false, amountSpecified, ZERO_BYTES);
        assertEq(result.amount0(), amountSpecified);
    }

    // --- Deployers.swapNativeInput() tests --- //
    function test_swapNativeInput_helper_zeroForOne_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swapNativeInput(nativeKey, true, amountSpecified, ZERO_BYTES, 100 wei);
        assertEq(result.amount0(), amountSpecified);
    }

    function test_swapNativeInput_helper_zeroForOne_exactOutput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swapNativeInput(nativeKey, true, amountSpecified, ZERO_BYTES, 200 wei); // overpay
        assertEq(result.amount1(), amountSpecified);
    }

    function test_swapNativeInput_helper_oneForZero_exactInput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swapNativeInput(nativeKey, false, amountSpecified, ZERO_BYTES, 0 wei);
        assertEq(result.amount1(), amountSpecified);
    }

    function test_swapNativeInput_helper_oneForZero_exactOutput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swapNativeInput(nativeKey, false, amountSpecified, ZERO_BYTES, 0 wei);
        assertEq(result.amount0(), amountSpecified);
    }

    function test_swapNativeInput_helper_nonnative_zeroForOne_exactInput() public {
        int256 amountSpecified = -100;
        vm.expectRevert();
        swapNativeInput(key, true, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_zeroForOne_exactOutput() public {
        int256 amountSpecified = 100;
        vm.expectRevert();
        swapNativeInput(key, true, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_oneForZero_exactInput() public {
        int256 amountSpecified = -100;
        vm.expectRevert();
        swapNativeInput(key, false, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_oneForZero_exactOutput() public {
        int256 amountSpecified = 100;
        vm.expectRevert();
        swapNativeInput(key, false, amountSpecified, ZERO_BYTES, 0 wei);
    }
}
