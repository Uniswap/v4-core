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

contract HooksTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    function testInitializeSucceedsWithHook() public {
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, new bytes(123));

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function testBeforeInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testAfterInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testModifyPositionSucceedsWithHook() public {
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, new bytes(111));
        assertEq(mockHooks.beforeModifyPositionData(), new bytes(111));
        assertEq(mockHooks.afterModifyPositionData(), new bytes(111));
    }

    function testBeforeModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function testAfterModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function testSwapSucceedsWithHook() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        swapRouter.swap(key, swapParams, testSettings, new bytes(222));
        assertEq(mockHooks.beforeSwapData(), new bytes(222));
        assertEq(mockHooks.afterSwapData(), new bytes(222));
    }

    function testBeforeSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function testAfterSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function testDonateSucceedsWithHook() public {
        donateRouter.donate(key, 100, 200, new bytes(333));
        assertEq(mockHooks.beforeDonateData(), new bytes(333));
        assertEq(mockHooks.afterDonateData(), new bytes(333));
    }

    function testBeforeDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function testAfterDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    // hook validation
    function testValidateHookAddressNoHooks(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));

        IHooks hookAddr = IHooks(address(preAddr));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeInitialize(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressAfterInitialize(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeAndAfterInitialize(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeModify(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_MODIFY_POSITION_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressAfterModify(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeAndAfterModify(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeInitializeAfterModify(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeSwap(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressAfterSwap(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeAndAfterSwap(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false
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
    }

    function testValidateHookAddressBeforeDonate(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false
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
    }

    function testValidateHookAddressAfterDonate(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: true
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
    }

    function testValidateHookAddressBeforeAndAfterDonate(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: true
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
    }

    function testValidateHookAddressAllHooks(uint152 addr) public {
        uint160 preAddr = uint160(uint256(addr));
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (0xfF << 152)));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
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
    }

    function testValidateHookAddressFailsAllHooks(uint152 addr, uint8 mask) public {
        uint160 preAddr = uint160(uint256(addr));
        vm.assume(mask != 0xff);
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 152)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
            })
        );
    }

    function testValidateHookAddressFailsNoHooks(uint152 addr, uint8 mask) public {
        uint160 preAddr = uint160(uint256(addr));
        vm.assume(mask != 0);
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 152)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
        Hooks.validateHookAddress(
            hookAddr,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
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
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0040000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x007840A85d5aF5BF1D1762f925bdADDC4201F984), 3000));
    }
}
