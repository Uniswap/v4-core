// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {FeeLibrary} from "../src/libraries/FeeLibrary.sol";
import {MockHooks} from "../src/test/MockHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Fees} from "../src/Fees.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {AccessLockHook} from "../src/test/AccessLockHook.sol";
import {IERC20Minimal} from "../src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";

contract HooksTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    MockHooks mockHooks;

    // Update this value when you add a new hook flag. And then update all appropriate asserts.
    uint256 hookPermissionCount = 10;
    uint256 clearAllHookPermisssionsMask;

    function setUp() public {
        clearAllHookPermisssionsMask = uint256(~uint160(0) >> (hookPermissionCount));

        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    function test_initialize_succeedsWithHook() public {
        initializeRouter.initialize(uninitializedKey, SQRT_RATIO_1_1, new bytes(123));

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function test_beforeInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        initializeRouter.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_afterInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        initializeRouter.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_modifyPosition_succeedsWithHook() public {
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, new bytes(111));
        assertEq(mockHooks.beforeModifyPositionData(), new bytes(111));
        assertEq(mockHooks.afterModifyPositionData(), new bytes(111));
    }

    function test_beforeModifyPosition_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_afterModifyPosition_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_swap_succeedsWithHook() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        swapRouter.swap(key, swapParams, testSettings, new bytes(222));
        assertEq(mockHooks.beforeSwapData(), new bytes(222));
        assertEq(mockHooks.afterSwapData(), new bytes(222));
    }

    function test_beforeSwap_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function test_afterSwap_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function test_donate_succeedsWithHook() public {
        donateRouter.donate(key, 100, 200, new bytes(333));
        assertEq(mockHooks.beforeDonateData(), new bytes(333));
        assertEq(mockHooks.afterDonateData(), new bytes(333));
    }

    function test_beforeDonate_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_afterDonate_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    // hook validation
    function testValidateHookAddressNoHooks(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(preAddr));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertTrue(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressAfterInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertTrue(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeAndAfterInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertTrue(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertTrue(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeModify(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_MODIFY_POSITION_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertTrue(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressAfterModify(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeAndAfterModify(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertTrue(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeInitializeAfterModify(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertTrue(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressAfterSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertTrue(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeAndAfterSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallBeforeSwap(hookAddr));
        assertTrue(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertTrue(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressAfterDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: true,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertTrue(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressBeforeAndAfterDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: true,
                noOp: false,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertTrue(Hooks.shouldCallBeforeDonate(hookAddr));
        assertTrue(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function test_validateHookAddress_accessLock(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.ACCESS_LOCK_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: true
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertFalse(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertFalse(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertFalse(Hooks.hasPermissionToNoOp(hookAddr));
        assertTrue(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressAllHooks(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        uint160 allHookBitsFlipped = (~uint160(0)) << uint160((160 - hookPermissionCount));
        IHooks hookAddr = IHooks(address(uint160(preAddr) | allHookBitsFlipped));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true,
                noOp: true,
                accessLock: true
            })
        );
        assertTrue(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertTrue(Hooks.shouldCallAfterInitialize(hookAddr));
        assertTrue(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallBeforeSwap(hookAddr));
        assertTrue(Hooks.shouldCallAfterSwap(hookAddr));
        assertTrue(Hooks.shouldCallBeforeDonate(hookAddr));
        assertTrue(Hooks.shouldCallAfterDonate(hookAddr));
        assertTrue(Hooks.hasPermissionToNoOp(hookAddr));
        assertTrue(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressNoOp(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(
            address(
                uint160(
                    preAddr | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
                        | Hooks.NO_OP_FLAG
                )
            )
        );
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false,
                noOp: true,
                accessLock: false
            })
        );
        assertFalse(Hooks.shouldCallBeforeInitialize(hookAddr));
        assertFalse(Hooks.shouldCallAfterInitialize(hookAddr));
        assertTrue(Hooks.shouldCallBeforeModifyPosition(hookAddr));
        assertFalse(Hooks.shouldCallAfterModifyPosition(hookAddr));
        assertTrue(Hooks.shouldCallBeforeSwap(hookAddr));
        assertFalse(Hooks.shouldCallAfterSwap(hookAddr));
        assertTrue(Hooks.shouldCallBeforeDonate(hookAddr));
        assertFalse(Hooks.shouldCallAfterDonate(hookAddr));
        assertTrue(Hooks.hasPermissionToNoOp(hookAddr));
        assertFalse(Hooks.hasPermissionToAccessLock(hookAddr));
    }

    function testValidateHookAddressFailsAllHooks(uint152 addr, uint8 mask) public {
        uint160 preAddr = uint160(uint256(addr));
        vm.assume(mask != 0xff8);
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 151)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true,
                noOp: true,
                accessLock: true
            })
        );
    }

    function testValidateHookAddressFailsNoHooks(uint160 addr, uint16 mask) public {
        uint160 preAddr = addr & uint160(0x007ffffFfffffffffFffffFFfFFFFFFffFFfFFff);
        mask = mask & 0xff80; // the last 7 bits are all 0, we just want a 9 bit mask
        vm.assume(mask != 0); // we want any combination except no hooks
        IHooks hookAddr = IHooks(address(preAddr | (uint160(mask) << 144)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false,
                accessLock: false
            })
        );
    }

    function testGas() public {
        snapStart("HooksShouldCallBeforeSwap");
        Hooks.shouldCallBeforeSwap(IHooks(address(0)));
        snapEnd();
    }

    function testIsValidHookAddressAnyFlags() public {
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x4000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x2000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x1000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0800000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0200000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0100000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0xf09840a85d5Af5bF1d1762f925bdaDdC4201f984), 3000));
    }

    function testIsValidHookAddressZeroAddress() public {
        assertTrue(Hooks.isValidHookAddress(IHooks(address(0)), 3000));
    }

    function testIsValidIfDynamicFee() public {
        assertTrue(
            Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), FeeLibrary.DYNAMIC_FEE_FLAG)
        );
        assertTrue(
            Hooks.isValidHookAddress(
                IHooks(0x0000000000000000000000000000000000000001), FeeLibrary.DYNAMIC_FEE_FLAG | uint24(3000)
            )
        );
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
    }

    function testInvalidIfNoFlags() public {
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0020000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x003840a85d5Af5Bf1d1762F925BDADDc4201f984), 3000));
    }
}
