// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Currency} from "../../contracts/libraries/CurrencyLibrary.sol";
import {IERC20Minimal} from "../../contracts/interfaces/external/IERC20Minimal.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {SqrtPriceMath} from "../../contracts/libraries/SqrtPriceMath.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {Deployers} from "./utils/Deployers.sol";

contract HooksTest is Test, Deployers, GasSnapshot {
    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    MockHooks mockHooks;
    PoolManager manager;
    IPoolManager.PoolKey key;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);
        (manager, key,) = Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));
        donateRouter = new PoolDonateTest(IPoolManager(address(manager)));
    }

    function testInitializeSucceedsWithHook() public {
        (PoolManager _manager,, bytes32 id) = Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
        (uint160 sqrtPriceX96,,) = _manager.getSlot0(id);
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);
    }

    function testFailBeforeInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
    }

    function testFailAfterInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
    }

    function testModifyPositionSucceedsWithHook() public {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testFailBeforeModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testFailAfterModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testSwapSucceedsWithHook() public {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testFailBeforeSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testFailAfterSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testDonateSucceedsWithHook() public {
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    function testFailBeforeDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    function testFailAfterDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    // hook validation
    function testValidateHookAddressNoHooks(uint152 preAddr) public {
        IHooks hookAddr = IHooks(address(uint160(preAddr)));
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

    function testValidateHookAddressBeforeInitialize(uint152 preAddr) public {
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

    function testValidateHookAddressAfterInitialize(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeAndAfterInitialize(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeModify(uint152 preAddr) public {
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

    function testValidateHookAddressAfterModify(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeAndAfterModify(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeSwap(uint152 preAddr) public {
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

    function testValidateHookAddressAfterSwap(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeAndAfterSwap(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeDonate(uint152 preAddr) public {
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

    function testValidateHookAddressAfterDonate(uint152 preAddr) public {
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

    function testValidateHookAddressBeforeAndAfterDonate(uint152 preAddr) public {
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

    function testValidateHookAddressAllHooks(uint152 preAddr) public {
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

    function testValidateHookAddressFailsAllHooks(uint152 preAddr, uint8 mask) public {
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

    function testValidateHookAddressFailsNoHooks(uint152 preAddr, uint8 mask) public {
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
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), Hooks.DYNAMIC_FEE));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
    }

    function testInvalidIfNoFlags() public {
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0010000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x009840A85D5af5BF1D1762f925BDaddC4201f984), 3000));
    }

    function addLiquidity(int24 tickLower, int24 tickUpper, int256 amount) internal {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        TestERC20(Currency.unwrap(key.currency1)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(tickLower, tickUpper, amount));
    }
}
