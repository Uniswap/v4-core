// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IFees} from "../src/interfaces/IFees.sol";
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
import {TestInvalidERC20} from "../src/test/TestInvalidERC20.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../src/test/PoolLockTest.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {FeeLibrary} from "../src/libraries/FeeLibrary.sol";
import {Position} from "../src/libraries/Position.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";
import {AmountHelpers} from "./utils/AmountHelpers.sol";

contract PoolManagerTest is Test, Deployers, GasSnapshot {
    using Hooks for IHooks;
    using PoolIdLibrary for PoolKey;
    using FeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    event LockAcquired();
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
    event ProtocolFeeUpdated(PoolId indexed id, uint16 protocolFee);
    event Transfer(
        address caller, address indexed sender, address indexed receiver, uint256 indexed id, uint256 amount
    );

    PoolLockTest lockTest;

    address ADDRESS_ZERO = address(0);
    address EMPTY_HOOKS = address(0xf000000000000000000000000000000000000000);
    address MOCK_HOOKS = address(0xfF00000000000000000000000000000000000000);

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));

        lockTest = new PoolLockTest(manager);
    }

    function test_bytecodeSize() public {
        snapSize("poolManager bytecode size", address(manager));
    }

    function test_feeControllerSet() public {
        deployFreshManager();
        assertEq(address(manager.protocolFeeController()), address(0));
        vm.expectEmit(false, false, false, true, address(manager));
        emit ProtocolFeeControllerUpdated(address(feeController));
        manager.setProtocolFeeController(feeController);
        assertEq(address(manager.protocolFeeController()), address(feeController));
    }

    function test_addLiquidity_failsIfNotInitialized() public {
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, LIQ_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_failsIfNotInitialized() public {
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, REMOVE_LIQ_PARAMS, ZERO_BYTES);
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
        address payable hookAddr = payable(MOCK_HOOKS);

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
        address payable hookAddr = payable(MOCK_HOOKS);

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
        address hookEmptyAddr = EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("addLiquidity with empty hook");
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_removeLiquidity_withHooks_gas() public {
        address hookEmptyAddr = EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        snapStart("removeLiquidity with empty hook");
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, ZERO_BYTES);
        snapEnd();
    }

    function test_mint_withHooks_EOAInitiated() public {
        address hookEmptyAddr = EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPool(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mintWithEmptyHookEOAInitiated");
        manager.lock(
            address(modifyLiquidityRouter),
            abi.encode(
                PoolModifyLiquidityTest.CallbackData(
                    address(this),
                    key,
                    IPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}),
                    ZERO_BYTES
                )
            )
        );

        snapEnd();
    }

    function test_swap_EOAInitiated(uint256 swapAmount) public {
        IPoolManager.ModifyLiquidityParams memory liqParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});
        modifyLiquidityRouter.modifyLiquidity(key, liqParams, ZERO_BYTES);

        (uint256 amount0,) = AmountHelpers.getMaxAmountInForPool(manager, Deployers.LIQ_PARAMS, key);
        // lower bound for precision purposes
        swapAmount = uint256(bound(swapAmount, 100, amount0));

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: SafeCast.toInt256(swapAmount),
            sqrtPriceLimitX96: SQRT_RATIO_1_2
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        snapStart("simpleSwapEOAInitiated");
        manager.lock(
            address(swapRouter),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, key, params, ZERO_BYTES))
        );
        snapEnd();
    }

    function test_swap_native_EOAInitiated() public {
        IPoolManager.ModifyLiquidityParams memory liqParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, liqParams, ZERO_BYTES);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: true});

        snapStart("simpleSwapNativeEOAInitiated");
        manager.lock{value: 100}(
            address(swapRouter),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, nativeKey, params, ZERO_BYTES))
        );
        snapEnd();
    }

    function test_invalidLockTarget() public {
        IPoolManager.ModifyLiquidityParams memory liqParams =
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(nativeKey, liqParams, ZERO_BYTES);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: true});

        // ensure reverts wen locking to variety of contracts which don't properly implement ILockCallback
        vm.expectRevert();
        manager.lock{value: 100}(
            address(0),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, nativeKey, params, ZERO_BYTES))
        );

        vm.expectRevert();
        manager.lock{value: 100}(
            address(this),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, nativeKey, params, ZERO_BYTES))
        );

        vm.expectRevert();
        manager.lock{value: 100}(
            address(manager),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, nativeKey, params, ZERO_BYTES))
        );

        vm.expectRevert();
        manager.lock{value: 100}(
            address(Currency.unwrap(currency0)),
            abi.encode(PoolSwapTest.CallbackData(address(this), testSettings, nativeKey, params, ZERO_BYTES))
        );
    }

    function test_swap_failsIfNotInitialized(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        key.fee = 100;
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: sqrtPriceX96});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectRevert(Pool.PoolNotInitialized.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsIfInitialized() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true);
        emit Swap(
            key.toId(), address(swapRouter), int128(100), int128(-98), 79228162514264329749955861424, 1e18, -1, 3000
        );

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithNativeTokensIfInitialized() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true);
        emit Swap(
            nativeKey.toId(),
            address(swapRouter),
            int128(100),
            int128(-98),
            79228162514264329749955861424,
            1e18,
            -1,
            3000
        );

        swapRouter.swap{value: 100}(nativeKey, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithHooksIfInitialized() public {
        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        address payable hookAddr = payable(MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(mockAddr), 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

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
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

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
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 10, -8, 79228162514264336880490487708, 1e18, -1, 100);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_gas() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        snapStart("simple swap");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withNative_gas() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        snapStart("simple swap with native");
        swapRouter.swap{value: 100}(nativeKey, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withHooks_gas() public {
        address hookEmptyAddr = EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        (key,) = initPoolAndAddLiquidity(currency0, currency1, mockHooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        snapStart("swap with hooks");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_mint6909IfOutputNotTaken_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

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
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

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
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 erc6909Balance = manager.balanceOf(address(this), uint256(uint160(Currency.unwrap(currency1))));
        assertEq(erc6909Balance, 98);

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 6909s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -25, sqrtPriceLimitX96: SQRT_RATIO_4_1});
        testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: false, currencyAlreadySent: false});

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
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_2_1});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit();
        emit Transfer(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE), 98);
        swapRouter.swap(nativeKey, params, testSettings, ZERO_BYTES);

        uint256 erc6909Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(CurrencyLibrary.NATIVE));
        assertEq(erc6909Balance, 98);

        // give permission for swapRouter to burn the 6909s
        manager.setOperator(address(swapRouter), true);

        // swap from currency0 to currency1, using 6909s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -25, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: false, currencyAlreadySent: false});

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
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_againstLiqWithNative_gas() public {
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        swapRouter.swap{value: 1 ether}(nativeKey, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity with native token");
        swapRouter.swap{value: 1 ether}(nativeKey, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_accruesProtocolFees(uint8 protocolFee1, uint8 protocolFee0) public {
        protocolFee0 = uint8(bound(protocolFee0, 4, type(uint8).max));
        protocolFee1 = uint8(bound(protocolFee1, 4, type(uint8).max));

        uint16 protocolFee = (uint16(protocolFee1) << 8) | (uint16(protocolFee0) & uint16(0xFF));

        feeController.setSwapFeeForPool(key.toId(), protocolFee);
        manager.setProtocolFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);

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

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1);
        swapRouter.swap(key, swapParams, PoolSwapTest.TestSettings(true, true, false), ZERO_BYTES);

        uint256 expectedTotalSwapFee = uint256(swapParams.amountSpecified) * key.fee / 1e6;
        uint256 expectedProtocolFee = expectedTotalSwapFee / protocolFee1;
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolFee);
    }

    function test_donate_failsIfNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Pool.PoolNotInitialized.selector));
        donateRouter.donate(uninitializedKey, 100, 100, ZERO_BYTES);
    }

    function test_donate_failsIfNoLiquidity(uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        (key,) = initPool(currency0, currency1, IHooks(address(0)), 100, sqrtPriceX96, ZERO_BYTES);

        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    // test successful donation if pool has liquidity
    function test_donate_succeedsWhenPoolHasLiquidity() public {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
        snapEnd();

        (, feeGrowthGlobal0X128, feeGrowthGlobal1X128,) = manager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 34028236692093846346337);
        assertEq(feeGrowthGlobal1X128, 68056473384187692692674);
    }

    function test_donate_succeedsForNativeTokensWhenPoolHasLiquidity() public {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(nativeKey.toId());
        assertEq(feeGrowthGlobal0X128, 0);
        assertEq(feeGrowthGlobal1X128, 0);

        donateRouter.donate{value: 100}(nativeKey, 100, 200, ZERO_BYTES);

        (, feeGrowthGlobal0X128, feeGrowthGlobal1X128,) = manager.pools(nativeKey.toId());
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

    function test_take_succeedsWithPoolWithLiquidityWithNativeToken() public {
        takeRouter.take{value: 1}(nativeKey, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function test_setProtocolFee_updatesProtocolFeeForInitializedPool(uint16 protocolFee) public {
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, 0);
        feeController.setSwapFeeForPool(key.toId(), protocolFee);

        uint8 fee0 = uint8(protocolFee >> 8);
        uint8 fee1 = uint8(protocolFee % 256);
        if ((0 < fee0 && fee0 < 4) || (0 < fee1 && fee1 < 4)) {
            vm.expectRevert(IFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
            manager.setProtocolFee(key);
        } else {
            vm.expectEmit(false, false, false, true);
            emit ProtocolFeeUpdated(key.toId(), protocolFee);
            manager.setProtocolFee(key);

            (slot0,,,) = manager.pools(key.toId());
            assertEq(slot0.protocolFee, protocolFee);
        }
    }

    function test_setProtocolFee_failsWithInvalidProtocolFeeControllers() public {
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, 0);

        manager.setProtocolFeeController(revertingFeeController);
        vm.expectRevert(IFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
        manager.setProtocolFee(key);

        manager.setProtocolFeeController(outOfBoundsFeeController);
        vm.expectRevert(IFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
        manager.setProtocolFee(key);

        manager.setProtocolFeeController(overflowFeeController);
        vm.expectRevert(IFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
        manager.setProtocolFee(key);

        manager.setProtocolFeeController(invalidReturnSizeFeeController);
        vm.expectRevert(IFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
        manager.setProtocolFee(key);
    }

    function test_collectProtocolFees_initializesWithProtocolFeeIfCalled() public {
        uint16 protocolFee = 1028; // 00000100 00000100

        // sets the upper 12 bits
        feeController.setSwapFeeForPool(uninitializedKey.toId(), uint16(protocolFee));

        initializeRouter.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.protocolFee, protocolFee);
    }

    function test_collectProtocolFees_ERC20_allowsOwnerToAccumulateFees_gas() public {
        uint16 protocolFee = 1028; // 00000100 00000100
        uint256 expectedFees = 7;

        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));
        manager.setProtocolFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(true, true, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        snapStart("erc20 collect protocol fees");
        manager.collectProtocolFees(address(1), currency0, expectedFees);
        snapEnd();
        assertEq(currency0.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_noop_gas(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable hookAddr = payable(
            address(
                uint160(
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
                        | Hooks.NO_OP_FLAG
                )
            )
        );

        vm.etch(hookAddr, vm.getDeployedCode("NoOpTestHooks.sol:NoOpTestHooks"));

        (key,) = initPool(currency0, currency1, IHooks(hookAddr), 100, SQRT_RATIO_1_1, ZERO_BYTES);

        // Test add liquidity
        snapStart("modify position with noop");
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether), ZERO_BYTES
        );
        snapEnd();

        // Swap
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        snapStart("swap with noop");
        delta = swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();

        // Donate
        snapStart("donate with noop");
        delta = donateRouter.donate(key, 0, 0, ZERO_BYTES);
        snapStart("donate with noop");
    }

    function test_noop_succeedsOnAllActions(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable hookAddr = payable(
            address(
                uint160(
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
                        | Hooks.NO_OP_FLAG
                )
            )
        );

        vm.etch(hookAddr, vm.getDeployedCode("NoOpTestHooks.sol:NoOpTestHooks"));

        (key,) = initPool(currency0, currency1, IHooks(hookAddr), 100, SQRT_RATIO_1_1, ZERO_BYTES);

        uint256 reserveBefore0 = manager.reservesOf(currency0);
        uint256 reserveBefore1 = manager.reservesOf(currency1);

        // Test add liquidity
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether), ZERO_BYTES
        );

        assertTrue(delta == BalanceDeltaLibrary.MAXIMUM_DELTA, "Max delta not returned");
        assertEq(manager.reservesOf(currency0), reserveBefore0);
        assertEq(manager.reservesOf(currency1), reserveBefore1);

        // Swap
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        delta = swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        assertTrue(delta == BalanceDeltaLibrary.MAXIMUM_DELTA, "Max delta not returned");
        assertEq(manager.reservesOf(currency0), reserveBefore0);
        assertEq(manager.reservesOf(currency1), reserveBefore1);

        // Donate
        delta = donateRouter.donate(key, 1 ether, 1 ether, ZERO_BYTES);

        assertTrue(delta == BalanceDeltaLibrary.MAXIMUM_DELTA, "Max delta not returned");
        assertEq(manager.reservesOf(currency0), reserveBefore0);
        assertEq(manager.reservesOf(currency1), reserveBefore1);
    }

    function test_noop_failsOnUninitializedPools(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable hookAddr = payable(
            address(
                uint160(
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
                        | Hooks.NO_OP_FLAG
                )
            )
        );

        vm.etch(hookAddr, vm.getDeployedCode("NoOpTestHooks.sol:NoOpTestHooks"));

        // Modify Position
        key = PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(hookAddr), tickSpacing: 10});

        vm.expectRevert(abi.encodeWithSelector(Pool.PoolNotInitialized.selector));
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether), ZERO_BYTES
        );

        // Swap
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectRevert(abi.encodeWithSelector(Pool.PoolNotInitialized.selector));
        delta = swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        // Donate
        vm.expectRevert(abi.encodeWithSelector(Pool.PoolNotInitialized.selector));
        delta = donateRouter.donate(key, 1 ether, 1 ether, ZERO_BYTES);
    }

    function test_noop_failsOnForbiddenFunctions(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable hookAddr = payable(
            address(
                uint160(
                    Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                        | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_DONATE_FLAG | Hooks.NO_OP_FLAG
                )
            )
        );

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        key = PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        // Fails at beforeInitialize hook when it returns a NoOp
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Now we let initialize succeed (so we can test other functions)
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Fails at afterAddLiquidity hook when it returns a NoOp
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        // Now we let the modify position succeed (so we can test other functions)
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, mockHooks.afterAddLiquidity.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        // Fails at afterSwap hook when it returns a NoOp
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2}),
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false}),
            ZERO_BYTES
        );

        // Fails at afterDonate hook when it returns a NoOp
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    function test_noop_failsWithoutNoOpFlag(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable hookAddr = payable(
            address(uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG))
        );

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        key = PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Fails at beforeAddLiquidity hook when it returns a NoOp but doesnt have permission
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        // Fails at beforeSwap hook when it returns a NoOp but doesnt have permission
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2}),
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false}),
            ZERO_BYTES
        );

        // Fails at beforeDonate hook when it returns a NoOp but doesnt have permission
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, Hooks.NO_OP_SELECTOR);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    function test_collectProtocolFees_ERC20_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint16 protocolFee = 1028; // 00000100 00000100
        uint256 expectedFees = 7;

        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));
        manager.setProtocolFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFee, protocolFee);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(true, true, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        manager.collectProtocolFees(address(1), currency0, 0);
        assertEq(currency0.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_nativeToken_allowsOwnerToAccumulateFees_gas() public {
        uint16 protocolFee = 1028; // 00000100 00000100
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        // set protocol fee before initializing the pool as it is fetched on initialization
        feeController.setSwapFeeForPool(nativeKey.toId(), uint16(protocolFee));
        manager.setProtocolFee(nativeKey);

        (Pool.Slot0 memory slot0,,,) = manager.pools(nativeKey.toId());
        assertEq(slot0.protocolFee, protocolFee);

        swapRouter.swap{value: 10000}(
            nativeKey,
            IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(true, true, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(nativeCurrency), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        snapStart("native collect protocol fees");
        manager.collectProtocolFees(address(1), nativeCurrency, expectedFees);
        snapEnd();
        assertEq(nativeCurrency.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function test_collectProtocolFees_nativeToken_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint16 protocolFee = 1028; // 00000100 00000100
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        feeController.setSwapFeeForPool(nativeKey.toId(), uint16(protocolFee));
        manager.setProtocolFee(nativeKey);

        (Pool.Slot0 memory slot0,,,) = manager.pools(nativeKey.toId());
        assertEq(slot0.protocolFee, protocolFee);

        swapRouter.swap{value: 10000}(
            nativeKey,
            IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2),
            PoolSwapTest.TestSettings(true, true, false),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(nativeCurrency), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        manager.collectProtocolFees(address(1), nativeCurrency, 0);
        assertEq(nativeCurrency.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function test_lock_NoOpIsOk() public {
        snapStart("gas overhead of no-op lock");
        lockTest.lock();
        snapEnd();
    }

    function test_lock_EmitsCorrectId() public {
        vm.expectEmit(false, false, false, true);
        emit LockAcquired();
        lockTest.lock();
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
