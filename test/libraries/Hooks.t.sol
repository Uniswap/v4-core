// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {MockHooks} from "src/test/MockHooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Currency} from "src/types/Currency.sol";
import {PoolManager} from "src/PoolManager.sol";
import {PoolSwapTest} from "src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "src/test/PoolDonateTest.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {ProtocolFees} from "src/ProtocolFees.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {IERC20Minimal} from "src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";

contract HooksTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using StateLibrary for IPoolManager;

    /// 1111 1111 1111 1100
    address payable ALL_HOOKS_ADDRESS = payable(0xFffC000000000000000000000000000000000000);
    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    function test_initialize_succeedsWithHook() public {
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, new bytes(123));

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1);
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function test_beforeInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function test_afterInitialize_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function test_beforeAfterAddLiquidity_beforeAfterRemoveLiquidity_succeedsWithHook() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18, 0), new bytes(222));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterAddLiquidity_calledWithPositiveLiquidityDelta() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 100, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
    }

    function test_beforeAfterRemoveLiquidity_calledWithZeroLiquidityDelta() public {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 0, 0), new bytes(222));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterRemoveLiquidity_calledWithPositiveLiquidityDelta() public {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(111));
    }

    function test_beforeAddLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_beforeRemoveLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_afterAddLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_afterRemoveLiquidity_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_swap_succeedsWithHook() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, swapParams, testSettings, new bytes(222));
        assertEq(mockHooks.beforeSwapData(), new bytes(222));
        assertEq(mockHooks.afterSwapData(), new bytes(222));
    }

    function test_beforeSwap_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_PRICE_1_1 + 60),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );
    }

    function test_afterSwap_invalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_PRICE_1_1 + 60),
            PoolSwapTest.TestSettings(true, true),
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
    function test_validateHookPermissions_noHooks(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeInitialize(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_afterInitialize(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAndAfterInitialize(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAddLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_afterAddLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAndAfterAddLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeRemoveLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_afterRemoveLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAfterRemoveLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeInitializeAfterAddLiquidity(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeSwap(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_afterSwap(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAndAfterSwap(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeDonate(uint160 addr) public view {
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_afterDonate(uint160 addr) public view {
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
                afterDonate: true,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_beforeAndAfterDonate(uint160 addr) public view {
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
                afterDonate: true,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
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
        assertFalse(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertFalse(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_allHooks(uint160 addr) public view {
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
                afterDonate: true,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: true,
                afterRemoveLiquidityReturnDelta: true
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
        assertTrue(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG));
        assertTrue(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG));
    }

    function test_validateHookPermissions_failsAllHooks(uint152 addr, uint16 mask) public {
        uint160 preAddr = uint160(uint256(addr));
        mask = mask & 0xfffc; // the last 7 bits are all 0, we just want a 14 bit mask
        vm.assume(mask != 0xfffc); // we want any combination except all hooks
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 151)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));
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
                afterDonate: true,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: true,
                afterRemoveLiquidityReturnDelta: true
            })
        );
    }

    function test_validateHookPermissions_failsNoHooks(uint160 addr, uint16 mask) public {
        uint160 preAddr = addr & uint160(0x007ffffFfffffffffFffffFFfFFFFFFffFFfFFff);
        mask = mask & 0xfffc; // the last 7 bits are all 0, we just want a 14 bit mask
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
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    function testGas() public {
        snapStart("HooksShouldCallBeforeSwap");
        IHooks(address(0)).hasPermission(Hooks.BEFORE_SWAP_FLAG);
        snapEnd();
    }

    function test_isValidHookAddress_valid_anyFlags() public pure {
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x4000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x2000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x1000000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0800000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0400000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0200000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0100000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0080000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0x0040000000000000000000000000000000000000), 3000));
        assertTrue(Hooks.isValidHookAddress(IHooks(0xf00040A85D5af5bf1d1762f925BDAddc4201f984), 3000));
    }

    function testIsValidHookAddress_valid_zeroAddressFixedFee() public pure {
        assertTrue(Hooks.isValidHookAddress(IHooks(address(0)), 3000));
    }

    function testIsValidHookAddress_invalid_zeroAddressWithDynamicFee() public pure {
        assertFalse(Hooks.isValidHookAddress(IHooks(address(0)), LPFeeLibrary.DYNAMIC_FEE_FLAG));
    }

    function testIsValidHookAddress_invalid_returnsDeltaWithoutHookFlag(uint160 addr) public view {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermisssionsMask);
        IHooks hookAddr = IHooks(address(uint160(preAddr | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG)));
        assertFalse(Hooks.isValidHookAddress(hookAddr, 3000));
        hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG)));
        assertFalse(Hooks.isValidHookAddress(hookAddr, 3000));
        hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG)));
        assertFalse(Hooks.isValidHookAddress(hookAddr, 3000));
        hookAddr = IHooks(address(uint160(preAddr | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG)));
        assertFalse(Hooks.isValidHookAddress(hookAddr, 3000));
    }

    function test_isValidHookAddress_valid_noFlagsWithDynamicFee() public pure {
        assertTrue(
            Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), LPFeeLibrary.DYNAMIC_FEE_FLAG)
        );
        assertTrue(
            Hooks.isValidHookAddress(
                IHooks(0x0000000000000000000000000000000000000001), LPFeeLibrary.DYNAMIC_FEE_FLAG | uint24(3000)
            )
        );
        assertTrue(Hooks.isValidHookAddress(IHooks(0x8000000000000000000000000000000000000000), 3000));
    }

    function test_isValidHookAddress_invalid_noFlagsNoDynamicFee() public pure {
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0000000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x0001000000000000000000000000000000000001), 3000));
        assertFalse(Hooks.isValidHookAddress(IHooks(0x000340A85D5AF5bf1D1762F925BdaddC4201f984), 3000));
    }
}
