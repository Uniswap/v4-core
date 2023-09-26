// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {IFees} from "../../contracts/interfaces/IFees.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/types/Currency.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {MockContract} from "../../contracts/test/MockContract.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {EmptyTestHooks} from "../../contracts/test/EmptyTestHooks.sol";
import {PoolKey} from "../../contracts/types/PoolKey.sol";
import {BalanceDelta} from "../../contracts/types/BalanceDelta.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../../contracts/test/PoolLockTest.sol";
import {PoolId, PoolIdLibrary} from "../../contracts/types/PoolId.sol";
import {ProtocolFeeControllerTest} from "../../contracts/test/ProtocolFeeControllerTest.sol";
import {FeeLibrary} from "../../contracts/libraries/FeeLibrary.sol";
import {Position} from "../../contracts/libraries/Position.sol";

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

    Pool.State state;
    PoolManager manager;
    PoolDonateTest donateRouter;
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
        modifyPositionRouter = new PoolModifyPositionTest(manager);

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
    }

    function testPoolManagerInitialize(PoolKey memory key, uint160 sqrtPriceX96) public {
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
            assertEq(slot0.protocolFees >> 12, 0);
        }
    }

    function testPoolManagerInitializeForNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
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

    function testPoolManagerInitializeSucceedsWithHooks(uint160 sqrtPriceX96) public {
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

    function testPoolManagerInitializeSucceedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
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

    function testPoolManagerInitializeSucceedsWithEmptyHooks(uint160 sqrtPriceX96) public {
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

    function testPoolManagerInitializeRevertsWithSameTokenCombo(uint160 sqrtPriceX96) public {
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

    function testPoolManagerInitializeRevertsWhenPoolAlreadyInitialized(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function testPoolManagerInitializeFailsWithIncorrectSelectors() public {
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

    function testPoolManagerInitializeSucceedsWithCorrectSelectors() public {
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

    function testPoolManagerInitializeFailsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
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

    function testPoolManagerInitializeFailsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 0});

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function testPoolManagerInitializeFailsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: -1});

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
    }

    function testPoolManagerFeeControllerSet() public {
        assertEq(address(manager.protocolFeeController()), address(0));
        vm.expectEmit(false, false, false, true, address(manager));
        emit ProtocolFeeControllerUpdated(address(protocolFeeController));
        manager.setProtocolFeeController(protocolFeeController);
        assertEq(address(manager.protocolFeeController()), address(protocolFeeController));
    }

    function testPoolManagerFetchFeeWhenController(uint160 sqrtPriceX96) public {
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

    function testGasPoolManagerInitialize() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        snapStart("initialize");
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        snapEnd();
    }

    function testMintFailsIfNotInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});
        vm.expectRevert();
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
    }

    function testMintSucceedsIfInitialized(uint160 sqrtPriceX96) public {
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

    function testMintSucceedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
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

    function testMintSucceedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
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

    function testMintFailsWithIncorrectSelectors() public {
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

    function testMintSucceedsWithCorrectSelectors() public {
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

    function testGasMint() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mint");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100}), ZERO_BYTES
        );
        snapEnd();
    }

    function testGasMintWithNative() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
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

    function testGasMintWithHooks() public {
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

    function testSwapFailsIfNotInitialized(uint160 sqrtPriceX96) public {
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

    function testSwapSucceedsIfInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_2, 0, -6932, 3000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwapSucceedsWithNativeTokensIfInitialized() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_2, 0, -6932, 3000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function testSwapSucceedsWithHooksIfInitialized() public {
        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)));
        address payable hookAddr = payable(MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(mockAddr), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        BalanceDelta balanceDelta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        bytes32 beforeSelector = MockHooks.beforeSwap.selector;
        bytes memory beforeParams = abi.encode(address(swapRouter), key, params, ZERO_BYTES);

        bytes32 afterSelector = MockHooks.afterSwap.selector;
        bytes memory afterParams = abi.encode(address(swapRouter), key, params, balanceDelta, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams));
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1);
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams));
    }

    function testSwapFailsWithIncorrectSelectors() public {
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
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

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

    function testSwapSucceedsWithCorrectSelectors() public {
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
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_2, 0, -6932, 100);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);
    }

    function testGasSwap() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("simple swap");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testGasSwapWithNative() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("swap with native");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testGasSwapWithHooks() public {
        address hookEmptyAddr = EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: mockHooks, tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        snapStart("swap with hooks");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testSwapMintERC1155IfOutputNotTaken() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000}),
            ZERO_BYTES
        );

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 erc1155Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc1155Balance, 98);
    }

    function testSwapUse1155AsInput() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000}),
            ZERO_BYTES
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
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        erc1155Balance = manager.balanceOf(address(this), CurrencyLibrary.toId(currency1));
        assertEq(erc1155Balance, 71);
    }

    function testGasSwapAgainstLiq() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000}),
            ZERO_BYTES
        );

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testGasSwapAgainstLiqWithNative() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
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

    function testDonateFailsIfNotInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    function testDonateFailsIfNoLiquidity(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100, ZERO_BYTES);
    }

    // test successful donation if pool has liquidity
    function testDonateSucceedsWhenPoolHasLiquidity() public {
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

    function testDonateSucceedsForNativeTokensWhenPoolHasLiquidity() public {
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

    function testDonateFailsWithIncorrectSelectors() public {
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

    function testDonateSucceedsWithCorrectSelectors() public {
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

    function testGasDonateOneToken() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params, ZERO_BYTES);

        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0, ZERO_BYTES);
        snapEnd();
    }

    function testNoOpLockIsOk() public {
        snapStart("gas overhead of no-op lock");
        lockTest.lock();
        snapEnd();
    }

    function testLockEmitsCorrectId() public {
        vm.expectEmit(false, false, false, true);
        emit LockAcquired();
        lockTest.lock();
    }

    uint256 constant POOL_SLOT = 10;
    uint256 constant TICKS_OFFSET = 4;

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

    function testGetPosition() public {
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
