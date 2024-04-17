// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IProtocolFeeController} from "../src/interfaces/IProtocolFeeController.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockHooks} from "../src/test/MockHooks.sol";
import {MockContract} from "../src/test/MockContract.sol";
import {EmptyTestHooks} from "../src/test/EmptyTestHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolModifyLiquidityTest} from "../src/test/PoolModifyLiquidityTest.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../src/types/BalanceDelta.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolSettleTest} from "../src/test/PoolSettleTest.sol";
import {TestInvalidERC20} from "../src/test/TestInvalidERC20.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolEmptyUnlockTest} from "../src/test/PoolEmptyUnlockTest.sol";
import {Action} from "../src/test/PoolNestedActionsTest.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {SwapFeeLibrary} from "../src/libraries/SwapFeeLibrary.sol";
import {Position} from "../src/libraries/Position.sol";
import {Constants} from "./utils/Constants.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {AmountHelpers} from "./utils/AmountHelpers.sol";
import {ProtocolFeeLibrary} from "../src/libraries/ProtocolFeeLibrary.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";

contract PoolManagerTest is Test, Deployers, GasSnapshot {
    using Hooks for IHooks;
    using PoolIdLibrary for PoolKey;
    using SwapFeeLibrary for uint24;
    using CurrencyLibrary for Currency;
    using ProtocolFeeLibrary for uint24;

    event UnlockCallback();
    event ProtocolFeeControllerUpdated(address feeController);
    event ModifyLiquidity(
        PoolId indexed poolId, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event Transfer(
        address caller, address indexed sender, address indexed receiver, uint256 indexed id, uint256 amount
    );

    PoolEmptyUnlockTest emptyUnlockRouter;

    uint24 constant MAX_FEE_BOTH_TOKENS = (2500 << 12) | 2500; // 2500 2500

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));

        emptyUnlockRouter = new PoolEmptyUnlockTest(manager);
    }

    function test_bytecodeSize() public {
        snapSize("poolManager bytecode size", address(manager));
    }

    function test_setProtocolFeeController_succeeds() public {
        deployFreshManager();
        assertEq(address(manager.protocolFeeController()), address(0));
        vm.expectEmit(false, false, false, true, address(manager));
        emit ProtocolFeeControllerUpdated(address(feeController));
        manager.setProtocolFeeController(feeController);
        assertEq(address(manager.protocolFeeController()), address(feeController));
    }

    function test_setProtocolFeeController_failsIfNotOwner() public {
        deployFreshManager();
        assertEq(address(manager.protocolFeeController()), address(0));

        vm.prank(address(1)); // not the owner address
        vm.expectRevert("UNAUTHORIZED");
        manager.setProtocolFeeController(feeController);
        assertEq(address(manager.protocolFeeController()), address(0));
    }

    function test_addLiquidity_failsIfNotInitialized() public {
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.modifyLiquidity(uninitializedKey, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_failsIfNotInitialized() public {
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_succeedsIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            LIQ_PARAMS.tickLower,
            LIQ_PARAMS.tickUpper,
            LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeedsIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            REMOVE_LIQ_PARAMS.tickLower,
            REMOVE_LIQ_PARAMS.tickUpper,
            REMOVE_LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_succeedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            nativeKey.toId(),
            address(modifyLiquidityRouter),
            LIQ_PARAMS.tickLower,
            LIQ_PARAMS.tickUpper,
            LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            nativeKey.toId(),
            address(modifyLiquidityRouter),
            REMOVE_LIQ_PARAMS.tickLower,
            REMOVE_LIQ_PARAMS.tickUpper,
            REMOVE_LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable mockAddr =
            payable(address(uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)));
        address payable hookAddr = payable(Constants.MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(currency0, currency1, IHooks(mockAddr), 3000, sqrtPriceX96, ZERO_BYTES);

        BalanceDelta balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        bytes32 beforeSelector = MockHooks.beforeAddLiquidity.selector;
        bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, LIQ_PARAMS, ZERO_BYTES);
        bytes32 afterSelector = MockHooks.afterAddLiquidity.selector;
        bytes memory afterParams = abi.encode(address(modifyLiquidityRouter), key, LIQ_PARAMS, balanceDelta, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function test_removeLiquidity_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable mockAddr =
            payable(address(uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)));
        address payable hookAddr = payable(Constants.MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPool(currency0, currency1, IHooks(mockAddr), 3000, sqrtPriceX96, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        BalanceDelta balanceDelta = modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);

        bytes32 beforeSelector = MockHooks.beforeRemoveLiquidity.selector;
        bytes memory beforeParams = abi.encode(address(modifyLiquidityRouter), key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
        bytes32 afterSelector = MockHooks.afterRemoveLiquidity.selector;
        bytes memory afterParams =
            abi.encode(address(modifyLiquidityRouter), key, REMOVE_LIQ_PARAMS, balanceDelta, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function test_addLiquidity_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));

        // Fails at beforeAddLiquidity hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        // Fail at afterAddLiquidity hook.
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));

        // Fails at beforeRemoveLiquidity hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);

        // Fail at afterRemoveLiquidity hook.
        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, mockHooks.beforeAddLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, mockHooks.afterAddLiquidity.selector);

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            LIQ_PARAMS.tickLower,
            LIQ_PARAMS.tickUpper,
            LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, mockHooks.beforeRemoveLiquidity.selector);
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, mockHooks.afterRemoveLiquidity.selector);

        vm.expectEmit(true, true, true, true);
        emit ModifyLiquidity(
            key.toId(),
            address(modifyLiquidityRouter),
            REMOVE_LIQ_PARAMS.tickLower,
            REMOVE_LIQ_PARAMS.tickUpper,
            REMOVE_LIQ_PARAMS.liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
    }

    function test_addLiquidity_6909() public {
        // convert test tokens into ERC6909 claims
        claimsRouter.deposit(currency0, address(this), 10_000e18);
        claimsRouter.deposit(currency1, address(this), 10_000e18);
        assertEq(manager.balanceOf(address(this), currency0.toId()), 10_000e18);
        assertEq(manager.balanceOf(address(this), currency1.toId()), 10_000e18);

        uint256 currency0BalanceBefore = currency0.balanceOfSelf();
        uint256 currency1BalanceBefore = currency1.balanceOfSelf();
        uint256 currency0PMBalanceBefore = currency0.balanceOf(address(manager));
        uint256 currency1PMBalanceBefore = currency1.balanceOf(address(manager));

        // allow liquidity router to burn our 6909 tokens
        manager.setOperator(address(modifyLiquidityRouter), true);

        // add liquidity with 6909: settleUsingBurn=true, takeClaims=true (unused)
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES, true, true);

        assertLt(manager.balanceOf(address(this), currency0.toId()), 10_000e18);
        assertLt(manager.balanceOf(address(this), currency1.toId()), 10_000e18);

        // ERC20s are unspent
        assertEq(currency0.balanceOfSelf(), currency0BalanceBefore);
        assertEq(currency1.balanceOfSelf(), currency1BalanceBefore);

        // PoolManager did not receive net-new ERC20s
        assertEq(currency0.balanceOf(address(manager)), currency0PMBalanceBefore);
        assertEq(currency1.balanceOf(address(manager)), currency1PMBalanceBefore);
    }

    function test_removeLiquidity_6909() public {
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        assertEq(manager.balanceOf(address(this), currency0.toId()), 0);
        assertEq(manager.balanceOf(address(this), currency1.toId()), 0);

        uint256 currency0BalanceBefore = currency0.balanceOfSelf();
        uint256 currency1BalanceBefore = currency1.balanceOfSelf();
        uint256 currency0PMBalanceBefore = currency0.balanceOf(address(manager));
        uint256 currency1PMBalanceBefore = currency1.balanceOf(address(manager));

        // remove liquidity as 6909: settleUsingBurn=true (unused), takeClaims=true
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES, true, true);

        assertTrue(manager.balanceOf(address(this), currency0.toId()) > 0);
        assertTrue(manager.balanceOf(address(this), currency1.toId()) > 0);

        // ERC20s are unspent
        assertEq(currency0.balanceOfSelf(), currency0BalanceBefore);
        assertEq(currency1.balanceOfSelf(), currency1BalanceBefore);

        // PoolManager did lose ERC-20s
        assertEq(currency0.balanceOf(address(manager)), currency0PMBalanceBefore);
        assertEq(currency1.balanceOf(address(manager)), currency1PMBalanceBefore);
    }

    function test_addLiquidity_gas() public {
        snapStart("addLiquidity");
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_removeLiquidity_gas() public {
        snapStart("removeLiquidity");
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_addLiquidity_withNative_gas() public {
        snapStart("addLiquidity with native token");
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_removeLiquidity_withNative_gas() public {
        snapStart("removeLiquidity with native token");
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, REMOVE_LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_addLiquidity_withHooks_gas() public {
        address hookEmptyAddr = Constants.EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("addLiquidity with empty hook");
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_removeLiquidity_withHooks_gas() public {
        address hookEmptyAddr = Constants.EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        snapStart("removeLiquidity with empty hook");
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_failsIfNotInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        key.fee = 100;
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: sqrtPriceX96});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectRevert(Pool.PoolNotInitialized.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsIfInitialized() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true);
        emit Swap(
            key.toId(), address(swapRouter), int128(-100), int128(98), 79228162514264329749955861424, 1e18, -1, 3000
        );

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_failsIfLocked() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.swap(key, swapParams, ZERO_BYTES);
    }

    function test_swap_succeedsWithNativeTokensIfInitialized() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true);
        emit Swap(
            nativeKey.toId(),
            address(swapRouter),
            int128(-100),
            int128(98),
            79228162514264329749955861424,
            1e18,
            -1,
            3000
        );

        swapRouter.swap{value: 100}(nativeKey, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithHooksIfInitialized() public {
        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        address payable hookAddr = payable(Constants.MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(mockAddr), 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        BalanceDelta balanceDelta = swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        bytes32 beforeSelector = MockHooks.beforeSwap.selector;
        bytes memory beforeParams = abi.encode(address(swapRouter), key, swapParams, ZERO_BYTES);

        bytes32 afterSelector = MockHooks.afterSwap.selector;
        bytes memory afterParams = abi.encode(address(swapRouter), key, swapParams, balanceDelta, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function test_swap_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        // Fails at beforeSwap hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        // Fail at afterSwap hook.
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), -10, 8, 79228162514264336880490487708, 1e18, -1, 100);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_gas() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        snapStart("simple swap");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withNative_gas() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        snapStart("simple swap with native");
        swapRouter.swap{value: 100}(nativeKey, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withHooks_gas() public {
        address hookEmptyAddr = Constants.EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        snapStart("swap with hooks");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_mint6909IfOutputNotTaken_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        snapStart("swap mint output as 6909");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        uint256 erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc6909Balance, 98);
    }

    function test_swap_mint6909IfNativeOutputNotTaken_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE), 98);
        snapStart("swap mint native output as 6909");
        swapRouter.swap(nativeKey, params, testSettings, ZERO_BYTES);
        snapEnd();

        uint256 erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE));
        assertEq(erc6909Balance, 98);
    }

    function test_swap_burn6909AsInput_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 erc6909Balance = manager.balanceOf(address(this), uint256(uint160(Currency.unwrap(currency1))));
        assertEq(erc6909Balance, 98);

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 6909s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 25, sqrtPriceLimitX96: SQRT_RATIO_4_1});
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(this), address(0), CurrencyLibrary.toId(currency1), 27);
        snapStart("swap burn 6909 for input");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc6909Balance, 71);
    }

    function test_swap_burnNative6909AsInput_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE), 98);
        swapRouter.swap(nativeKey, params, testSettings, ZERO_BYTES);

        uint256 erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE));
        assertEq(erc6909Balance, 98);

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency0 to currency1, using 6909s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 25, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: true, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(this), address(0), CurrencyLibrary.toId(CurrencyLibrary.NATIVE), 27);
        snapStart("swap burn native 6909 for input");
        // don't have to send in native currency since burning 6909 for input
        swapRouter.swap(nativeKey, params, testSettings, ZERO_BYTES);
        snapEnd();

        erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE));
        assertEq(erc6909Balance, 71);
    }

    function test_swap_againstLiq_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_againstLiqWithNative_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false, currencyAlreadySent: false});

        swapRouter.swap{value: 1 ether}(nativeKey, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity with native token");
        swapRouter.swap{value: 1 ether}(nativeKey, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_accruesProtocolFees(uint16 protocolFee0, uint16 protocolFee1) public {
        protocolFee0 = uint16(bound(protocolFee0, 1, 2500));
        protocolFee1 = uint16(bound(protocolFee1, 1, 2500));

        uint24 protocolFee = (uint24(protocolFee1) << 12) | uint24(protocolFee0);

        vm.prank(address(feeController));
        manager.setProtocolFee(key, protocolFee);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, protocolFee);

        // Add liquidity - Fees dont accrue for positive liquidity delta.
        IPoolManager.ModifyLiquidityParams memory params = LIQ_PARAMS;
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        // Remove liquidity - Fees dont accrue for negative liquidity delta.
        params.liquidityDelta = -LIQ_PARAMS.liquidityDelta;
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        // Now re-add the liquidity to test swap
        params.liquidityDelta = LIQ_PARAMS.liquidityDelta;
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams(false, -10000, TickMath.MAX_SQRT_RATIO - 1);
        swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(false, false, false), ZERO_BYTES);

        uint256 expectedTotalSwapFee = uint256(-swapParams.amountSpecified) * key.fee / 1e6;
        uint256 expectedProtocolFee = expectedTotalSwapFee * protocolFee1 / 1e4;
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolFee);
    }

    function test_donate_failsIfNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Pool.PoolNotInitialized.selector));
        donateRouter.donate(uninitializedKey, 100, 100, ZERO_BYTES);
    }

    function test_donate_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.donate(key, 100, 100, ZERO_BYTES);
    }

    function test_donate_failsIfNoLiquidity(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        (key,) = initPool(currency0, currency1, IHooks(address(0)), 100, sqrtPriceX96, ZERO_BYTES);

        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    // test successful donation if pool has liquidity
    function test_donate_succeedsWhenPoolHasLiquidity() public {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(key.toId());
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
        snapEnd();

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(key.toId());
        assertEq(feeGrowthGlobal0X128, 34028236692093846346337);
        assertEq(feeGrowthGlobal1X128, 68056473384187692692674);
    }

    function test_donate_succeedsForNativeTokensWhenPoolHasLiquidity() public {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(nativeKey.toId());
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        donateRouter.donate{value: 100}(nativeKey, 100, 200, ZERO_BYTES);

        (feeGrowthGlobal0X128, feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(nativeKey.toId());
        assertEq(feeGrowthGlobal0X128, 34028236692093846346337);
        assertEq(feeGrowthGlobal1X128, 68056473384187692692674);
    }

    function test_donate_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        // Fails at beforeDonate hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);

        // Fail at afterDonate hook.
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_donate_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 100, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_donate_OneToken_gas() public {
        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0, ZERO_BYTES);
        snapEnd();
    }

    function test_take_failsWithNoLiquidity() public {
        deployFreshManagerAndRouters();

        vm.expectRevert();
        takeRouter.take(key, 100, 0);
    }

    function test_take_failsWithInvalidTokensThatDoNotReturnTrueOnTransfer() public {
        TestInvalidERC20 invalidToken = new TestInvalidERC20(2 ** 255);
        Currency invalidCurrency = Currency.wrap(address(invalidToken));
        invalidToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        invalidToken.approve(address(takeRouter), type(uint256).max);

        bool currency0Invalid = invalidCurrency < currency0;

        (key,) = initPoolAndAddLiquidity(
            (currency0Invalid ? invalidCurrency : currency0),
            (currency0Invalid ? currency0 : invalidCurrency),
            IHooks(address(0)),
            3000,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );

        (uint256 amount0, uint256 amount1) = currency0Invalid ? (1, 0) : (0, 1);
        vm.expectRevert(CurrencyLibrary.ERC20TransferFailed.selector);
        takeRouter.take(key, amount0, amount1);

        // should not revert when non zero amount passed in for valid currency
        // assertions inside takeRouter because it takes then settles
        (amount0, amount1) = currency0Invalid ? (0, 1) : (1, 0);
        takeRouter.take(key, amount0, amount1);
    }

    function test_take_succeedsWithPoolWithLiquidity() public {
        takeRouter.take(key, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function test_take_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.take(key.currency0, address(this), 1);
    }

    function test_take_succeedsWithPoolWithLiquidityWithNativeToken() public {
        takeRouter.take{value: 1}(nativeKey, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function test_settle_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.settle(key.currency0);
    }

    function test_settle_revertsSendingNativeWithToken() public {
        vm.expectRevert(IPoolManager.NonZeroNativeValue.selector);
        settleRouter.settle{value: 1}(key);
    }

    function test_mint_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.mint(address(this), key.currency0.toId(), 1);
    }

    function test_burn_failsIfLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.burn(address(this), key.currency0.toId(), 1);
    }

    function test_setProtocolFee_updatesProtocolFeeForInitializedPool(uint24 protocolFee) public {
        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        uint16 fee0 = protocolFee.getZeroForOneFee();
        uint16 fee1 = protocolFee.getOneForZeroFee();
        vm.prank(address(feeController));
        if ((fee0 > 2500) || (fee1 > 2500)) {
            vm.expectRevert(IProtocolFees.InvalidProtocolFee.selector);
            manager.setProtocolFee(key, protocolFee);
        } else {
            vm.expectEmit(false, false, false, true);
            emit IProtocolFees.ProtocolFeeUpdated(key.toId(), protocolFee);
            manager.setProtocolFee(key, protocolFee);

            (,, slot0ProtocolFee,) = manager.getSlot0(key.toId());
            assertEq(slot0ProtocolFee, protocolFee);
        }
    }

    function test_setProtocolFee_failsWithInvalidFee() public {
        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.prank(address(feeController));
        vm.expectRevert(IProtocolFees.InvalidProtocolFee.selector);
        manager.setProtocolFee(key, MAX_FEE_BOTH_TOKENS + 1);
    }

    function test_setProtocolFee_failsWithInvalidCaller() public {
        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, 0);

        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        manager.setProtocolFee(key, MAX_FEE_BOTH_TOKENS);
    }

    function test_collectProtocolFees_initializesWithProtocolFeeIfCalled() public {
        feeController.setProtocolFeeForPool(uninitializedKey.toId(), MAX_FEE_BOTH_TOKENS);

        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(slot0ProtocolFee, MAX_FEE_BOTH_TOKENS);
    }

    function test_collectProtocolFees_revertsIfCallerIsNotController() public {
        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        manager.collectProtocolFees(address(1), currency0, 0);
    }

    function test_collectProtocolFees_ERC20_accumulateFees_gas() public {
        uint256 expectedFees = 7;

        uint24 protocolFee = MAX_FEE_BOTH_TOKENS;
        vm.prank(address(feeController));
        manager.setProtocolFee(key, protocolFee);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, MAX_FEE_BOTH_TOKENS);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, -10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(false, false, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        snapStart("erc20 collect protocol fees");
        manager.collectProtocolFees(address(1), currency0, expectedFees);
        snapEnd();
        assertEq(currency0.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_ERC20_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint256 expectedFees = 7;

        uint24 protocolFee = MAX_FEE_BOTH_TOKENS;
        vm.prank(address(feeController));
        manager.setProtocolFee(key, protocolFee);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(key.toId());
        assertEq(slot0ProtocolFee, MAX_FEE_BOTH_TOKENS);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, -10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(false, false, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedFees);
        assertEq(currency1.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        manager.collectProtocolFees(address(1), currency1, 0);
        assertEq(currency1.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
    }

    function test_collectProtocolFees_nativeToken_accumulateFees_gas() public {
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        // set protocol fee before initializing the pool as it is fetched on initialization
        uint24 protocolFee = MAX_FEE_BOTH_TOKENS;
        vm.prank(address(feeController));
        manager.setProtocolFee(nativeKey, protocolFee);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(nativeKey.toId());
        assertEq(slot0ProtocolFee, MAX_FEE_BOTH_TOKENS);

        swapRouter.swap{value: 10000}(
            nativeKey,
            IPoolManager.SwapParams(true, -10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(false, false, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(nativeCurrency), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        snapStart("native collect protocol fees");
        manager.collectProtocolFees(address(1), nativeCurrency, expectedFees);
        snapEnd();
        assertEq(nativeCurrency.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function test_collectProtocolFees_nativeToken_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        uint24 protocolFee = MAX_FEE_BOTH_TOKENS;
        vm.prank(address(feeController));
        manager.setProtocolFee(nativeKey, protocolFee);

        (,, uint24 slot0ProtocolFee,) = manager.getSlot0(nativeKey.toId());
        assertEq(slot0ProtocolFee, MAX_FEE_BOTH_TOKENS);

        swapRouter.swap{value: 10000}(
            nativeKey,
            IPoolManager.SwapParams(true, -10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(false, false, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(nativeCurrency), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        vm.prank(address(feeController));
        manager.collectProtocolFees(address(1), nativeCurrency, 0);
        assertEq(nativeCurrency.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function test_unlock_EmitsCorrectId() public {
        vm.expectEmit(false, false, false, true);
        emit UnlockCallback();
        emptyUnlockRouter.unlock();
    }

    Action[] actions;

    function test_unlock_cannotBeCalledTwiceByCaller() public {
        actions = [Action.NESTED_SELF_UNLOCK];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    function test_unlock_cannotBeCalledTwiceByDifferentCallers() public {
        actions = [Action.NESTED_EXECUTOR_UNLOCK];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    // function testExtsloadForPoolPrice() public {
    //     IPoolManager.key = IPoolManager.PoolKey({
    //         currency0: currency0,
    //         currency1: currency1,
    //         fee: 100,
    //         hooks: IHooks(address(0)),
    //         tickSpacing: 10
    //     });
    //     manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

    //     PoolId poolId = key.toId();
    //     snapStart("poolExtsloadSlot0");
    //     bytes32 slot0Bytes = manager.extsload(keccak256(abi.encode(poolId, POOL_SLOT)));
    //     snapEnd();

    //     uint160 sqrtPriceX96Extsload;
    //     assembly {
    //         sqrtPriceX96Extsload := and(slot0Bytes, sub(shl(160, 1), 1))
    //     }
    //     (uint160 sqrtPriceX96Slot0,,,,,) = manager.getSlot0(poolId);

    //     // assert that extsload loads the correct storage slot which matches the true slot0
    //     assertEq(sqrtPriceX96Extsload, sqrtPriceX96Slot0);
    // }

    // function testExtsloadMultipleSlots() public {
    //     IPoolManager.key = IPoolManager.PoolKey({
    //         currency0: currency0,
    //         currency1: currency1,
    //         fee: 100,
    //         hooks: IHooks(address(0)),
    //         tickSpacing: 10
    //     });
    //     manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

    //     // populate feeGrowthGlobalX128 struct w/ modify + swap
    //     modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-120, 120, 5 ether));
    //     swapRouter.swap(
    //         key,
    //         IPoolManager.SwapParams(false, 1 ether, TickMath.MAX_SQRT_RATIO - 1),
    //         PoolSwapTest.TestSettings(true, true, false)
    //     );
    //     swapRouter.swap(
    //         key,
    //         IPoolManager.SwapParams(true, 5 ether, TickMath.MIN_SQRT_RATIO + 1),
    //         PoolSwapTest.TestSettings(true, true, false)
    //     );

    //     PoolId poolId = key.toId();
    //     snapStart("poolExtsloadTickInfoStruct");
    //     bytes memory value = manager.extsload(bytes32(uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + 1), 2);
    //     snapEnd();

    //     uint256 feeGrowthGlobal0X128Extsload;
    //     uint256 feeGrowthGlobal1X128Extsload;
    //     assembly {
    //         feeGrowthGlobal0X128Extsload := and(mload(add(value, 0x20)), sub(shl(256, 1), 1))
    //         feeGrowthGlobal1X128Extsload := and(mload(add(value, 0x40)), sub(shl(256, 1), 1))
    //     }

    //     assertEq(feeGrowthGlobal0X128Extsload, 408361710565269213475534193967158);
    //     assertEq(feeGrowthGlobal1X128Extsload, 204793365386061595215803889394593);
    // }

    function test_getPosition() public {
        Position.Info memory managerPosition =
            manager.getPosition(key.toId(), address(modifyLiquidityRouter), -120, 120);
        assert(LIQ_PARAMS.liquidityDelta > 0);
        assertEq(managerPosition.liquidity, uint128(uint256(LIQ_PARAMS.liquidityDelta)));
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
