// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {FeeLibrary} from "../../src/libraries/FeeLibrary.sol";
import {MockHooks} from "../../src/test/MockHooks.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../../src/test/PoolDonateTest.sol";
import {Deployers} from "./Deployers.sol";
import {Fees} from "../../src/Fees.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {AccessLockHook} from "../../src/test/AccessLockHook.sol";
import {IERC20Minimal} from "../../src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";

/// @notice Testing Deployers.swap() and Deployers.swapNativeInput()
contract SwapHelperTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;

    address payable ALL_HOOKS_ADDRESS = payable(0xfFf0000000000000000000000000000000000000);
    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    // --- Deployers.swap() tests --- //
    function test_swap_helper_zeroForOne_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    function test_swap_helper_zeroForOne_exactOutput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount1()), amountSpecified);
    }

    function test_swap_helper_oneForZero_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(key, false, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount1()), amountSpecified);
    }

    function test_swap_helper_oneForZero_exactOutput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(key, false, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    function test_swap_helper_native_zeroForOne_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(nativeKey, true, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    function test_swap_helper_native_zeroForOne_exactOutput() public {
        int256 amountSpecified = -100;
        vm.expectRevert();
        swap(nativeKey, true, amountSpecified, ZERO_BYTES);
    }

    function test_swap_helper_native_oneForZero_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swap(nativeKey, false, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount1()), amountSpecified);
    }

    function test_swap_helper_native_oneForZero_exactOutput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swap(nativeKey, false, amountSpecified, ZERO_BYTES);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    // --- Deployers.swapNativeInput() tests --- //
    function test_swapNativeInput_helper_zeroForOne_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swapNativeInput(nativeKey, true, amountSpecified, ZERO_BYTES, 100 wei);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    function test_swapNativeInput_helper_zeroForOne_exactOutput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swapNativeInput(nativeKey, true, amountSpecified, ZERO_BYTES, 200 wei); // overpay
        assertEq(int256(result.amount1()), amountSpecified);
    }

    function test_swapNativeInput_helper_oneForZero_exactInput() public {
        int256 amountSpecified = 100;
        BalanceDelta result = swapNativeInput(nativeKey, false, amountSpecified, ZERO_BYTES, 0 wei);
        assertEq(int256(result.amount1()), amountSpecified);
    }

    function test_swapNativeInput_helper_oneForZero_exactOutput() public {
        int256 amountSpecified = -100;
        BalanceDelta result = swapNativeInput(nativeKey, false, amountSpecified, ZERO_BYTES, 0 wei);
        assertEq(int256(result.amount0()), amountSpecified);
    }

    function test_swapNativeInput_helper_nonnative_zeroForOne_exactInput() public {
        int256 amountSpecified = 100;
        vm.expectRevert();
        swapNativeInput(key, true, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_zeroForOne_exactOutput() public {
        int256 amountSpecified = -100;
        vm.expectRevert();
        swapNativeInput(key, true, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_oneForZero_exactInput() public {
        int256 amountSpecified = 100;
        vm.expectRevert();
        swapNativeInput(key, false, amountSpecified, ZERO_BYTES, 0 wei);
    }

    function test_swapNativeInput_helper_nonnative_oneForZero_exactOutput() public {
        int256 amountSpecified = -100;
        vm.expectRevert();
        swapNativeInput(key, false, amountSpecified, ZERO_BYTES, 0 wei);
    }
}
