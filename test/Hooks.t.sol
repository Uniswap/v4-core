// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {SwapFeeLibrary} from "../src/libraries/SwapFeeLibrary.sol";
import {MockHooks} from "../src/test/MockHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {ProtocolFees} from "../src/ProtocolFees.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {IERC20Minimal} from "../src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";

contract HooksTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;

    /// 1111 1111 1100
    address payable ALL_HOOKS_ADDRESS = payable(0xFfC0000000000000000000000000000000000000);
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
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, new bytes(123));

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function test_beforeInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_afterInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_beforeAfterAddLiquidity_beforeAfterRemoveLiquidity_succeedsWithHook() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18), new bytes(222));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterAddLiquidity_calledWithPositiveLiquidityDelta() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 100), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
    }

    function test_beforeAfterRemoveLiquidity_calledWithZeroLiquidityDelta() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 0), new bytes(222));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterRemoveLiquidity_calledWithPositiveLiquidityDelta() public {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), new bytes(111));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(111));
    }

    function test_beforeAddLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_beforeRemoveLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_afterAddLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_afterRemoveLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_swap_succeedsWithHook() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

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
            PoolSwapTest.TestSettings(false, false, false),
            ZERO_BYTES
        );
    }

    function test_afterSwap_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60),
            PoolSwapTest.TestSettings(false, false, false),
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
    function test_ValidateHookAddress_noHooks(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(preAddr));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_afterInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);

        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAndAfterInitialize(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAddLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_afterAddLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_ADD_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAndAfterAddLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeRemoveLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_afterRemoveLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAfterRemoveLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeInitializeAfterAddLiquidity(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr =
            IHooks(address(uint160(preAddr | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_afterSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAndAfterSwap(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_afterDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: true
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_beforeAndAfterDonate(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG)));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: true
            })
        );
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_allHooks(uint160 addr) public {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        uint160 allHookBitsFlipped = (~uint160(0)) << uint160((160 - hookPermissionCount));
        IHooks hookAddr = IHooks(address(uint160(preAddr) | allHookBitsFlipped));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
            })
        );
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG));
    }

    function test_validateHookAddress_failsAllHooks(uint152 addr, uint8 mask) public {
        uint160 preAddr = uint160(uint256(addr));
        vm.assume(mask != 0xff8);
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 151)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
        Hooks.validateHookPermissions(
            hookAddr,
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
            })
        );
    }

    function test_validateHookAddress_failsNoHooks(uint160 addr, uint16 mask) public {
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
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function testGas() public {
        snapStart("HooksShouldCallBeforeSwap");
        IHooks(address(0)).hasPermission(Hooks.BEFORE_SWAP_FLAG);
        snapEnd();
    }

    function test_isValidHookAddress_anyFlags() public {
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x4000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x2000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x1000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0800000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0200000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0100000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0xf09840a85d5Af5bF1d1762f925bdaDdC4201f984), 3000));
    }

    function testIsValidHookAddress_zeroAddress() public {
        assertTrue(Hooks.isValidHookAddress(IHooks(address(0)), 3000));
    }

    function test_isValidIfDynamicFee() public {
        assertTrue(
            Hooks.isValidHookAddress(
                IHooks(0x0000000000000000000000000000000000000001), SwapFeeLibrary.DYNAMIC_FEE_FLAG
            )
        );
        assertTrue(
            Hooks.isValidHookAddress(
                IHooks(0x0000000000000000000000000000000000000001), SwapFeeLibrary.DYNAMIC_FEE_FLAG | uint24(3000)
            )
        );
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
    }

    function test_invalidIfNoFlags() public {
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0020000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x003840a85d5Af5Bf1d1762F925BDADDc4201f984), 3000));
    }
}
