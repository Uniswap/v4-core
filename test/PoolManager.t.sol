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
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {ProtocolFeeControllerTest} from "../src/test/ProtocolFeeControllerTest.sol";
import {PoolTakeTest} from "../src/test/PoolTakeTest.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockHooks} from "../src/test/MockHooks.sol";
import {MockContract} from "../src/test/MockContract.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {EmptyTestHooks} from "../src/test/EmptyTestHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {TestInvalidERC20} from "../src/test/TestInvalidERC20.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../src/test/PoolLockTest.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {ProtocolFeeControllerTest} from "../src/test/ProtocolFeeControllerTest.sol";
import {FeeLibrary} from "../src/libraries/FeeLibrary.sol";
import {Position} from "../src/libraries/Position.sol";

import {console2} from "forge-std/console2.sol";

contract PoolManagerTest is Test, Deployers, TokenFixture, GasSnapshot, IERC1155Receiver {
    using Hooks for IHooks;
    using Pool for Pool.State;
    using PoolIdLibrary for PoolKey;
    using FeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    event LockAcquired();
    event ProtocolFeeControllerUpdated(address protocolFeeController);
    event Initialize(
        PoolId indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    event ModifyPosition(
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
    event TransferSingle(
        address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount
    );
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFees);

    Pool.State state;
    PoolManager manager;
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    ProtocolFeeControllerTest feeController;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolLockTest lockTest;
    ProtocolFeeControllerTest protocolFeeController;

    address ADDRESS_ZERO = address(0);
    address EMPTY_HOOKS = address(0xf000000000000000000000000000000000000000);
    address ALL_HOOKS = address(0xff00000000000000000000000000000000000001);
    address MOCK_HOOKS = address(0xfF00000000000000000000000000000000000000);

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        modifyPositionRouter = new PoolModifyPositionTest(manager);
        feeController = new ProtocolFeeControllerTest();

        lockTest = new PoolLockTest(manager);
        swapRouter = new PoolSwapTest(manager);
        protocolFeeController = new ProtocolFeeControllerTest();

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(donateRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(donateRouter), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(takeRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(takeRouter), 10 ether);
    }

    function test_bytecodeSize() public {
        snapSize("poolManager bytecode size", address(manager));
    }

    function test_initialize(PoolKey memory key, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        // tested in Hooks.t.sol
        key.hooks = IHooks(address(0));

        if (key.fee & FeeLibrary.STATIC_FEE_MASK >= 1000000) {
            vm.expectRevert(abi.encodeWithSelector(IFees.FeeTooLarge.selector));
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        } else if (key.tickSpacing > manager.MAX_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        } else if (key.tickSpacing < manager.MIN_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        } else if (key.currency0 > key.currency1) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrenciesInitializedOutOfOrder.selector));
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        } else if (!key.hooks.isValidHookAddress(key.fee)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(key.hooks)));
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        } else {
            vm.expectEmit(true, true, true, true);
            emit Initialize(key.toId(), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
            manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

            (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
            assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(slot0.protocolFees, 0);
        }
    }

    function test_initialize_forNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        vm.expectEmit(true, true, true, true);
        emit Initialize(key.toId(), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolFees >> 12, 0);
        assertEq(slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
    }

    function test_initialize_succeedsWithHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        address payable hookAddr = payable(MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(mockAddr), tickSpacing: 60});

        int24 tick = manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);

        bytes32 beforeSelector = MockHooks.beforeInitialize.selector;
        bytes memory beforeParams = abi.encode(address(this), key, sqrtPriceX96, ZERO_BYTES);

        bytes32 afterSelector = MockHooks.afterInitialize.selector;
        bytes memory afterParams = abi.encode(address(this), key, sqrtPriceX96, tick, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function test_initialize_succeedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: manager.MAX_TICK_SPACING()
        });

        vm.expectEmit(true, true, true, true);
        emit Initialize(key.toId(), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_succeedsWithEmptyHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address hookEmptyAddr = EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: mockHooks, tickSpacing: 60});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
    }

    function test_initialize_revertsWithIdenticalTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        // Both currencies are currency0
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency0, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        vm.expectRevert(IPoolManager.CurrenciesInitializedOutOfOrder.selector);
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_revertsWithSameTokenCombo(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        PoolKey memory keyInvertedCurrency =
            PoolKey({currency0: currency1, currency1: currency0, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(IPoolManager.CurrenciesInitializedOutOfOrder.selector);
        manager.initialize(keyInvertedCurrency, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_revertsWhenPoolAlreadyInitialized(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));

        // Fails at beforeInitialize hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Fail at afterInitialize hook.
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_initialize_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, mockHooks.afterInitialize.selector);

        vm.expectEmit(true, true, true, true);
        emit Initialize(key.toId(), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: manager.MAX_TICK_SPACING() + 1
        });

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 0});

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: -1});

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_gas() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        snapStart("initialize");
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        snapEnd();
    }

    function test_feeControllerSet() public {
        assertEq(address(manager.protocolFeeController()), address(0));
        vm.expectEmit(false, false, false, true, address(manager));
        emit ProtocolFeeControllerUpdated(address(protocolFeeController));
        manager.setProtocolFeeController(protocolFeeController);
        assertEq(address(manager.protocolFeeController()), address(protocolFeeController));
    }

    function test_fetchFeeWhenController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.setProtocolFeeController(protocolFeeController);

        uint16 poolProtocolFee = 4;
        protocolFeeController.setSwapFeeForPool(key.toId(), poolProtocolFee);

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolFees >> 12, poolProtocolFee);
    }

    function test_mint_failsIfNotInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});
        vm.expectRevert();
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
    }

    function test_mint_succeedsIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(key.toId(), address(modifyPositionRouter), 0, 60, 100);

        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
    }

    function test_mint_succeedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(key.toId(), address(modifyPositionRouter), 0, 60, 100);

        modifyPositionRouter.modifyPosition{value: 100}(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
    }

    function test_mint_succeedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address payable mockAddr =
            payable(address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));
        address payable hookAddr = payable(MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(mockAddr), tickSpacing: 60});

        IPoolManager.ModifyPositionParams memory params =
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

        BalanceDelta balanceDelta = modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        bytes32 beforeSelector = MockHooks.beforeModifyPosition.selector;
        bytes memory beforeParams = abi.encode(address(modifyPositionRouter), key, params, ZERO_BYTES);
        bytes32 afterSelector = MockHooks.afterModifyPosition.selector;
        bytes memory afterParams = abi.encode(address(modifyPositionRouter), key, params, balanceDelta, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function test_mint_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        IPoolManager.ModifyPositionParams memory params =
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));

        // Fails at beforeModifyPosition hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        // Fail at afterModifyPosition hook.
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, mockHooks.beforeModifyPosition.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
    }

    function test_mint_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        IPoolManager.ModifyPositionParams memory params =
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, mockHooks.beforeModifyPosition.selector);
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, mockHooks.afterModifyPosition.selector);

        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(key.toId(), address(modifyPositionRouter), 0, 60, 100);

        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
    }

    function test_mint_gas() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mint");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
        snapEnd();
    }

    function test_mint_withNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mint with native token");
        modifyPositionRouter.modifyPosition{value: 100}(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
        snapEnd();
    }

    function test_mint_withHooks_gas() public {
        address hookEmptyAddr = EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: mockHooks, tickSpacing: 60});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mint with empty hook");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
        snapEnd();
    }

    function test_swap_failsIfNotInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: sqrtPriceX96});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectRevert();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsIfInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit Swap(
            key.toId(), address(swapRouter), int128(100), int128(-98), 79228162514264329749955861424, 1e18, -1, 3000
        );

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithNativeTokensIfInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition{value: 1 ether}(key, liqParams, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit Swap(
            key.toId(), address(swapRouter), int128(100), int128(-98), 79228162514264329749955861424, 1e18, -1, 3000
        );

        swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithHooksIfInitialized() public {
        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        address payable hookAddr = payable(MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(mockAddr), tickSpacing: 60});

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);

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

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        IPoolManager.ModifyPositionParams memory params =
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        // Fails at beforeModifyPosition hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        // Fail at afterModifyPosition hook.
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 10, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 10, -8, 79228162514264336880490487708, 1e18, -1, 100);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function test_swap_gas() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);

        snapStart("simple swap");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition{value: 1 ether}(key, liqParams, ZERO_BYTES);

        snapStart("simple swap");
        swapRouter.swap{value: 100}(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_withHooks_gas() public {
        address hookEmptyAddr = EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: mockHooks, tickSpacing: 60});

        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        snapStart("swap with hooks");
        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_GasMintERC1155IfOutputNotTaken() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18}), ZERO_BYTES
        );

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        snapStart("swap mint 1155 as output");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        uint256 erc1155Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc1155Balance, 98);
    }

    function test_swap_GasUse1155AsInput() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18}), ZERO_BYTES
        );
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 erc1155Balance = manager.balanceOf(address(this), uint256(uint160(Currency.unwrap(currency1))));
        assertEq(erc1155Balance, 98);

        // give permission for swapRouter to burn the 1155s
        manager.setApprovalForAll(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 1155s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -25, sqrtPriceLimitX96: SQRT_RATIO_4_1});

        testSettings = PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: false});

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(manager), address(manager), address(0), CurrencyLibrary.toId(currency1), 27);
        snapStart("swap with 1155 as input");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        erc1155Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc1155Balance, 71);
    }

    function test_swap_againstLiq_gas() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18}), ZERO_BYTES
        );

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_swap_againstLiqWithNative_gas() public {
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition{value: 1 ether}(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1 ether}),
            ZERO_BYTES
        );

        swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity with native token");
        swapRouter.swap{value: 1 ether}(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function test_donate_failsIfNotInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    function test_donate_failsIfNoLiquidity(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    // test successful donation if pool has liquidity
    function test_donate_succeedsWhenPoolHasLiquidity() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
        snapEnd();

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function test_donate_succeedsForNativeTokensWhenPoolHasLiquidity() public {
        vm.deal(address(this), 1 ether);

        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition{value: 1}(key, params, ZERO_BYTES);
        donateRouter.donate{value: 100}(key, 100, 200, ZERO_BYTES);

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(key.toId());
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function test_donate_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
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

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: mockHooks, tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_donate_OneToken_gas() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0, ZERO_BYTES);
        snapEnd();
    }

    function test_take_failsWithNoLiquidity() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        vm.expectRevert();
        takeRouter.take(key, 100, 0);
    }

    function test_take_failsWithInvalidTokensThatDoNotReturnTrueOnTransfer() public {
        TestInvalidERC20 invalidToken = new TestInvalidERC20(2**255);
        Currency invalidCurrency = Currency.wrap(address(invalidToken));
        bool currency0Invalid = invalidCurrency < currency0;
        PoolKey memory key = PoolKey({
            currency0: currency0Invalid ? invalidCurrency : currency0,
            currency1: currency0Invalid ? currency0 : invalidCurrency,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        invalidToken.approve(address(modifyPositionRouter), type(uint256).max);
        invalidToken.approve(address(takeRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency0)).approve(address(takeRouter), type(uint256).max);

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 1000);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        (uint256 amount0, uint256 amount1) = currency0Invalid ? (1, 0) : (0, 1);
        vm.expectRevert();
        takeRouter.take(key, amount0, amount1);

        // should not revert when non zero amount passed in for valid currency
        // assertions inside takeRouter because it takes then settles
        (amount0, amount1) = currency0Invalid ? (0, 1) : (1, 0);
        takeRouter.take(key, amount0, amount1);
    }

    function test_take_succeedsWithPoolWithLiquidity() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
        takeRouter.take(key, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function test_take_succeedsWithPoolWithLiquidityWithNativeToken() public {
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition{value: 100}(key, params, ZERO_BYTES);
        takeRouter.take{value: 1}(key, 1, 1); // assertions inside takeRouter because it takes then settles
    }

    function test_setProtocolFee_updatesProtocolFeeForInitializedPool() public {
        uint24 protocolFee = 4;

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, 0);
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        vm.expectEmit(false, false, false, true);
        emit ProtocolFeeUpdated(key.toId(), protocolFee << 12);
        manager.setProtocolFees(key);
    }

    function test_collectProtocolFees_initializesWithProtocolFeeIfCalled() public {
        uint24 protocolFee = 260; // 0001 00 00 0100
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        // sets the upper 12 bits
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, protocolFee << 12);
    }

    function test_collectProtocolFees_ERC20_allowsOwnerToAccumulateFees() public {
        uint24 protocolFee = 260; // 0001 00 00 0100
        uint256 expectedFees = 7;

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, protocolFee << 12);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10 ether);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
        swapRouter.swap(
            key, IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2), PoolSwapTest.TestSettings(true, true), ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        manager.collectProtocolFees(address(1), currency0, expectedFees);
        assertEq(currency0.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_ERC20_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint24 protocolFee = 260; // 0001 00 00 0100
        uint256 expectedFees = 7;

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, protocolFee << 12);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10 ether);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);
        swapRouter.swap(
            key, IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2), PoolSwapTest.TestSettings(true, true), ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency0), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(currency0.balanceOf(address(1)), 0);
        manager.collectProtocolFees(address(1), currency0, 0);
        assertEq(currency0.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency0), 0);
    }

    function test_collectProtocolFees_nativeToken_allowsOwnerToAccumulateFees() public {
        uint24 protocolFee = 260; // 0001 00 00 0100
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        PoolKey memory key = PoolKey({
            currency0: nativeCurrency,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, protocolFee << 12);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10 ether);
        modifyPositionRouter.modifyPosition{value: 10 ether}(key, params, ZERO_BYTES);
        swapRouter.swap{value: 10000}(
            key, IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2), PoolSwapTest.TestSettings(true, true), ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(nativeCurrency), expectedFees);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(nativeCurrency.balanceOf(address(1)), 0);
        manager.collectProtocolFees(address(1), nativeCurrency, expectedFees);
        assertEq(nativeCurrency.balanceOf(address(1)), expectedFees);
        assertEq(manager.protocolFeesAccrued(nativeCurrency), 0);
    }

    function test_collectProtocolFees_nativeToken_returnsAllFeesIf0IsProvidedAsParameter() public {
        uint24 protocolFee = 260; // 0001 00 00 0100
        uint256 expectedFees = 7;
        Currency nativeCurrency = CurrencyLibrary.NATIVE;

        PoolKey memory key = PoolKey({
            currency0: nativeCurrency,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.setProtocolFeeController(IProtocolFeeController(address(feeController)));
        feeController.setSwapFeeForPool(key.toId(), uint16(protocolFee));

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolFees, protocolFee << 12);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10 ether);
        modifyPositionRouter.modifyPosition{value: 10 ether}(key, params, ZERO_BYTES);
        swapRouter.swap{value: 10000}(
            key, IPoolManager.SwapParams(true, 10000, SQRT_RATIO_1_2), PoolSwapTest.TestSettings(true, true), ZERO_BYTES
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
    //     IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
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
    //     IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
    //         currency0: currency0,
    //         currency1: currency1,
    //         fee: 100,
    //         hooks: IHooks(address(0)),
    //         tickSpacing: 10
    //     });
    //     manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

    //     // populate feeGrowthGlobalX128 struct w/ modify + swap
    //     modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 5 ether));
    //     swapRouter.swap(
    //         key,
    //         IPoolManager.SwapParams(false, 1 ether, TickMath.MAX_SQRT_RATIO - 1),
    //         PoolSwapTest.TestSettings(true, true)
    //     );
    //     swapRouter.swap(
    //         key,
    //         IPoolManager.SwapParams(true, 5 ether, TickMath.MIN_SQRT_RATIO + 1),
    //         PoolSwapTest.TestSettings(true, true)
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
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 5 ether), ZERO_BYTES);

        Position.Info memory managerPosition = manager.getPosition(key.toId(), address(modifyPositionRouter), -120, 120);

        assertEq(managerPosition.liquidity, 5 ether);
    }

    receive() external payable {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
