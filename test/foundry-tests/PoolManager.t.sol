// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

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
import {FullMath} from "../../contracts/libraries/FullMath.sol";
import {FixedPoint96} from "../../contracts/libraries/FixedPoint96.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";

contract PoolManagerTest is Test, Deployers, TokenFixture, GasSnapshot, IERC1155Receiver {
    using Hooks for IHooks;
    using Pool for Pool.State;
    using PoolIdLibrary for PoolKey;
    using FeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    event LockAcquired();
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
            assertEq(slot0.protocolSwapFee, 0);
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
        assertEq(slot0.protocolSwapFee, 0);
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

        uint8 poolProtocolFee = 4;
        protocolFeeController.setSwapFeeForPool(key.toId(), poolProtocolFee);

        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolSwapFee, poolProtocolFee);
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
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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

        BalanceDelta balanceDelta = modifyPositionRouter.modifyPosition(key, params);

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
        modifyPositionRouter.modifyPosition(key, params);

        // Fail at afterModifyPosition hook.
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, mockHooks.beforeModifyPosition.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyPositionRouter.modifyPosition(key, params);
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

        modifyPositionRouter.modifyPosition(key, params);
    }

    function testGasMint() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        snapStart("mint");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
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
        swapRouter.swap(key, params, testSettings);
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

        swapRouter.swap(key, params, testSettings);
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

        swapRouter.swap(key, params, testSettings);
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

        BalanceDelta balanceDelta = swapRouter.swap(key, params, testSettings);

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
        modifyPositionRouter.modifyPosition(key, params);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        // Fails at beforeModifyPosition hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings);

        // Fail at afterModifyPosition hook.
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(key, swapParams, testSettings);
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
        modifyPositionRouter.modifyPosition(key, params);

        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, mockHooks.beforeSwap.selector);
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, mockHooks.afterSwap.selector);

        vm.expectEmit(true, true, true, true);
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_2, 0, -6932, 100);

        swapRouter.swap(key, swapParams, testSettings);
    }

    function testGasSwap() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 3000, hooks: IHooks(address(0)), tickSpacing: 60});

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        swapRouter.swap(key, params, testSettings);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("simple swap");
        swapRouter.swap(key, params, testSettings);
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
        swapRouter.swap(key, params, testSettings);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: false});

        snapStart("swap with native");
        swapRouter.swap(key, params, testSettings);
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
        swapRouter.swap(key, params, testSettings);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});
        testSettings = PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        snapStart("swap with hooks");
        swapRouter.swap(key, params, testSettings);
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
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000})
        );

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings);

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
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000})
        );
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(swapRouter), address(0), address(this), CurrencyLibrary.toId(currency1), 98);
        swapRouter.swap(key, params, testSettings);

        uint256 erc1155Balance = manager.balanceOf(address(this), uint256(uint160(Currency.unwrap(currency1))));
        assertEq(erc1155Balance, 98);

        // give permission for swapRouter to burn the 1155s
        manager.setApprovalForAll(address(swapRouter), true);

        // swap from currency1 to currency0 again, using 1155s as input tokens
        params = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -25, sqrtPriceLimitX96: SQRT_RATIO_4_1});

        testSettings = PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: false});

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(manager), address(manager), address(0), CurrencyLibrary.toId(currency1), 27);
        swapRouter.swap(key, params, testSettings);

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
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000000000000000000})
        );

        swapRouter.swap(key, params, testSettings);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity");
        swapRouter.swap(key, params, testSettings);
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
            key, IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1 ether})
        );

        swapRouter.swap{value: 1 ether}(key, params, testSettings);

        params = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_4});

        snapStart("swap against liquidity with native token");
        swapRouter.swap{value: 1 ether}(key, params, testSettings);
        snapEnd();
    }

    function testDonateFailsIfNotInitialized() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    function testDonateFailsIfNoLiquidity(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    // test successful donation if pool has liquidity
    function testDonateSucceedsWhenPoolHasLiquidity() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);
        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200);
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
        modifyPositionRouter.modifyPosition{value: 1}(key, params);
        donateRouter.donate{value: 100}(key, 100, 200);

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
        modifyPositionRouter.modifyPosition(key, params);
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        // Fails at beforeDonate hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200);

        // Fail at afterDonate hook.
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200);
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
        modifyPositionRouter.modifyPosition(key, params);

        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);

        donateRouter.donate(key, 100, 200);
    }

    function testGasDonateOneToken() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);

        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0);
        snapEnd();
    }

    function testDonateTick_BelowActiveDirectBoundary() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, -10, 0, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, -20, -10, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = lpInfo1.tickLower;

        // Donate & check that balances were pulled to the pool.
        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo1.lpAddress), lpInfo1.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo1.lpAddress), lpInfo1.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_BelowActiveSkipOneBoundary() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, -10, 0, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, -20, -10, 1e18);
        LpInfo memory lpInfo2 = _createLpPosition(key, -30, -20, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = lpInfo2.tickLower;

        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));

        // Donate & check that balances were pulled to the pool.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo2.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo2.tickLower, lpInfo2.tickUpper, -lpInfo2.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo2.lpAddress), lpInfo2.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo2.lpAddress), lpInfo2.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_BelowActiveDirectMiddle() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, -10, 0, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, -20, -10, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = -15;

        // Donate & check that balances were pulled to the pool.
        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo1.lpAddress), lpInfo1.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo1.lpAddress), lpInfo1.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_BelowActiveSkipOneMiddle() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, -10, 0, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, -20, -10, 1e18);
        LpInfo memory lpInfo2 = _createLpPosition(key, -30, -20, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = -25;

        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));

        // Donate & check that balances were pulled to the pool.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo2.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo2.tickLower, lpInfo2.tickUpper, -lpInfo2.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo2.lpAddress), lpInfo2.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo2.lpAddress), lpInfo2.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_AboveActiveDirectBoundary() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, 0, 10, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, 10, 20, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = lpInfo1.tickLower;

        // Donate & check that balances were pulled to the pool.
        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Check te target position received donate proceeds.
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo1.lpAddress), lpInfo1.amount0 + lDonateAmount, 1, "LP1: amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo1.lpAddress), lpInfo1.amount1 + lDonateAmount, 1, "LP1: amount1 withdraw mismatch");

        // Check the other position did not receive any donate proceeds.
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo0.lpAddress), lpInfo0.amount0, 1, "LP0: amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo0.lpAddress), lpInfo0.amount1, 1, "LP0: amount1 withdraw mismatch");


        // Make sure we emptied the pool.
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_AboveActiveSkipOneBoundary() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, 0, 10, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, 10, 20, 1e18);
        LpInfo memory lpInfo2 = _createLpPosition(key, 20, 30, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = lpInfo2.tickLower;

        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));

        // Donate & check that balances were pulled to the pool.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo2.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo2.tickLower, lpInfo2.tickUpper, -lpInfo2.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo2.lpAddress), lpInfo2.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo2.lpAddress), lpInfo2.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_AboveActiveDirectMiddle() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, 0, 10, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, 10, 20, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = 15;

        // Donate & check that balances were pulled to the pool.
        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo1.lpAddress), lpInfo1.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo1.lpAddress), lpInfo1.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateTick_AboveActiveSkipOneMiddle() external {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create 2 LP positions, active tick and one tick above active.
        LpInfo memory lpInfo0 = _createLpPosition(key, 0, 10, 1e18);
        LpInfo memory lpInfo1 = _createLpPosition(key, 10, 20, 1e18);
        LpInfo memory lpInfo2 = _createLpPosition(key, 20, 30, 1e18);

        // Donate 2 eth of each asset to the position in range at tick 10 (tickLower = 10).
        uint256 lDonateAmount = 2 ether;
        uint256[] memory amounts0 = new uint[](1);
        amounts0[0] = lDonateAmount;
        uint256[] memory amounts1 = new uint[](1);
        amounts1[0] = lDonateAmount;
        int24[] memory ticks = new int24[](1);
        ticks[0] = 25;

        uint256 lBefore0 = key.currency0.balanceOf(address(manager));
        uint256 lBefore1 = key.currency1.balanceOf(address(manager));

        // Donate & check that balances were pulled to the pool.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), lBefore0 + lDonateAmount, "amount0 donation failed");
        assertEq(key.currency1.balanceOf(address(manager)), lBefore1 + lDonateAmount, "amount1 donation failed");

        // Close position that received the donate.
        vm.prank(lpInfo2.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo2.tickLower, lpInfo2.tickUpper, -lpInfo2.liquidity)
        );

        // Ensure users received their intended donations.
        assertApproxEqAbs(key.currency0.balanceOf(lpInfo2.lpAddress), lpInfo2.amount0 + lDonateAmount, 1, "amount0 withdraw mismatch");
        assertApproxEqAbs(key.currency1.balanceOf(lpInfo2.lpAddress), lpInfo2.amount1 + lDonateAmount, 1, "amount1 withdraw mismatch");

        // Redeem the other position and ensure pool is empty (math precision leaves some wei).
        vm.prank(lpInfo0.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo0.tickLower, lpInfo0.tickUpper, -lpInfo0.liquidity)
        );
        vm.prank(lpInfo1.lpAddress);
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(lpInfo1.tickLower, lpInfo1.tickUpper, -lpInfo1.liquidity)
        );
        assertLt(key.currency0.balanceOf(address(manager)), 10, "Too much amount0 dust");
        assertLt(key.currency1.balanceOf(address(manager)), 10, "Too much amount1 dust");
        assertEq(manager.getLiquidity(key.toId()), 0, "Liquidity left over");
    }

    function testDonateManyRangesBelowCurrentTick() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        uint256 nPositions = 3;
        uint256 donateAmount = 3 ether;

        LpInfo[] memory lpInfo = _createLpPositionsSymmetric(key, nPositions);

        uint256[] memory amounts0 = new uint[](nPositions);
        amounts0[0] = donateAmount;
        amounts0[1] = donateAmount;
        amounts0[2] = donateAmount;

        uint256[] memory amounts1 = new uint[](nPositions);
        amounts1[0] = donateAmount;
        amounts1[1] = donateAmount;
        amounts1[2] = donateAmount;

        int24[] memory ticks = new int24[](nPositions);
        ticks[0] = lpInfo[2].tickLower;
        ticks[1] = lpInfo[1].tickLower;
        ticks[2] = lpInfo[0].tickLower;

        uint256 liquidityBalance0 = key.currency0.balanceOf(address(manager));
        uint256 liquidityBalance1 = key.currency1.balanceOf(address(manager));

        // Donate and make sure all balances were pulled.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance0);
        assertEq(key.currency1.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance1);

        // Close all positions.
        for (uint256 i = 0; i < lpInfo.length; i++) {
            vm.prank(lpInfo[i].lpAddress);
            modifyPositionRouter.modifyPosition(
                key, IPoolManager.ModifyPositionParams(lpInfo[i].tickLower, lpInfo[i].tickUpper, -lpInfo[i].liquidity)
            );
        }

        // Ensure the pool was emptied (some wei rounding imprecision may remain).
        assertLt(key.currency0.balanceOf(address(manager)), 10);
        assertLt(key.currency1.balanceOf(address(manager)), 10);
        assertEq(manager.getLiquidity(key.toId()), 0);
    }

    function testDonateManyRangesAboveCurrentTick() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        uint256 nPositions = 3;
        uint256 donateAmount = 3 ether;
        LpInfo[] memory lpInfo = _createLpPositionsSymmetric(key, nPositions);

        uint256[] memory amounts0 = new uint[](nPositions);
        amounts0[0] = donateAmount;
        amounts0[1] = donateAmount;
        amounts0[2] = donateAmount;

        uint256[] memory amounts1 = new uint[](nPositions);
        amounts1[0] = donateAmount;
        amounts1[1] = donateAmount;
        amounts1[2] = donateAmount;

        int24[] memory ticks = new int24[](nPositions);
        ticks[0] = lpInfo[0].tickUpper;
        ticks[1] = lpInfo[1].tickUpper;
        ticks[2] = lpInfo[2].tickUpper - 1;

        uint256 liquidityBalance0 = key.currency0.balanceOf(address(manager));
        uint256 liquidityBalance1 = key.currency1.balanceOf(address(manager));

        // Donate and make sure all balances were pulled.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance0);
        assertEq(key.currency1.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance1);

        // Close all positions.
        for (uint256 i = 0; i < lpInfo.length; i++) {
            vm.prank(lpInfo[i].lpAddress);
            modifyPositionRouter.modifyPosition(
                key, IPoolManager.ModifyPositionParams(lpInfo[i].tickLower, lpInfo[i].tickUpper, -lpInfo[i].liquidity)
            );
        }

        // Ensure the pool was emptied (some wei rounding imprecision may remain).
        assertLt(key.currency0.balanceOf(address(manager)), 10);
        assertLt(key.currency1.balanceOf(address(manager)), 10);
        assertEq(manager.getLiquidity(key.toId()), 0);
    }

    function testDonateManyRangesBelowOnAndAboveCurrentTick() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, hooks: IHooks(address(0)), tickSpacing: 10});
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        uint256 nPositions = 3;
        uint256 donateAmount = 3 ether;
        LpInfo[] memory lpInfo = _createLpPositionsSymmetric(key, nPositions);

        uint256[] memory amounts0 = new uint[](nPositions);
        amounts0[0] = donateAmount;
        amounts0[1] = donateAmount;
        amounts0[2] = donateAmount;

        uint256[] memory amounts1 = new uint[](nPositions);
        amounts1[0] = donateAmount;
        amounts1[1] = donateAmount;
        amounts1[2] = donateAmount;

        int24[] memory ticks = new int24[](nPositions);
        ticks[0] = lpInfo[0].tickLower;
        ticks[1] = 0;
        ticks[2] = lpInfo[0].tickUpper;

        uint256 liquidityBalance0 = key.currency0.balanceOf(address(manager));
        uint256 liquidityBalance1 = key.currency1.balanceOf(address(manager));

        // Donate and make sure all balances were pulled.
        donateRouter.donateRange(key, amounts0, amounts1, ticks);
        assertEq(key.currency0.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance0);
        assertEq(key.currency1.balanceOf(address(manager)), donateAmount * nPositions + liquidityBalance1);

        // Close all positions.
        for (uint256 i = 0; i < lpInfo.length; i++) {
            vm.prank(lpInfo[i].lpAddress);
            modifyPositionRouter.modifyPosition(
                key, IPoolManager.ModifyPositionParams(lpInfo[i].tickLower, lpInfo[i].tickUpper, -lpInfo[i].liquidity)
            );
        }

        // Ensure the pool was emptied (some wei rounding imprecision may remain).
        assertLt(key.currency0.balanceOf(address(manager)), 10);
        assertLt(key.currency1.balanceOf(address(manager)), 10);
        assertEq(manager.getLiquidity(key.toId()), 0);
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

        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 5 ether));

        Position.Info memory managerPosition = manager.getPosition(key.toId(), address(modifyPositionRouter), -120, 120);

        assertEq(managerPosition.liquidity, 5 ether);
    }

    struct LpInfo {
        // address of the lp
        address lpAddress;
        // liquidity added
        int256 liquidity;
        // amount0 added by the LP
        uint256 amount0;
        // amount1 added by the LP
        uint256 amount1;
        // the lower tick the LP added to
        int24 tickLower;
        // the upper tick the LP added to
        int24 tickUpper;
    }

    function _createLpPositionsSymmetric(PoolKey memory key, uint256 nPositions)
        internal
        returns (LpInfo[] memory lpInfo)
    {
        lpInfo = new LpInfo[](nPositions);
        for (uint256 i = 0; i < nPositions; i++) {
            int24 tick = key.tickSpacing * int24(uint24(i + 1));

            lpInfo[i] = _createLpPositionSymmetric(key, tick);
        }
    }

    function _createLpPositionSymmetric(PoolKey memory key, int24 tick) private returns (LpInfo memory lpInfo) {
        uint256 amount = 1 ether;
        int256 liquidityAmount =
            int256(uint256(getLiquidityForAmount0(SQRT_RATIO_1_1, TickMath.getSqrtRatioAtTick(tick), amount)));

        lpInfo = _createLpPosition(key, -tick, tick, liquidityAmount);
    }

    function _createLpPosition(PoolKey memory key, int24 tickLower, int24 tickUpper, int256 liquidity)
        private
        returns (LpInfo memory lpInfo)
    {
        require(liquidity >= 0 && liquidity <= int256(uint256(type(uint128).max)));

        // Create a unique lp address.
        address lpAddr = address(bytes20(keccak256(abi.encode(tickLower, tickUpper))));

        // Compute & mint tokens required.
        // TODO: Assumes pool was initted at tick 0.
        (uint256 amount0, uint256 amount1 ) = getAmountsForLiquidity(TickMath.getSqrtRatioAtTick(0), TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(uint256(liquidity)));
        MockERC20(Currency.unwrap(currency0)).mint(lpAddr, amount0 + 1); // TODO: should we bake this in to the amount?
        MockERC20(Currency.unwrap(currency1)).mint(lpAddr, amount1 + 1); // TODO: should we bake this in to the amount?

        // Add the liquidity.
        vm.startPrank(lpAddr);
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), type(uint256).max);
        BalanceDelta delta =
            modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(tickLower, tickUpper, liquidity));
        vm.stopPrank();

        lpInfo = LpInfo({
            lpAddress: lpAddr,
            liquidity: int256(uint256(liquidity)),
            amount0: uint256(uint128(delta.amount0())),
            amount1: uint256(uint128(delta.amount1())),
            tickLower: tickLower,
            tickUpper: tickUpper
        });
    }

    function getLiquidityForAmount0(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        liquidity = uint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    function getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(
            uint256(liquidity) << FixedPoint96.RESOLUTION, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96
        ) / sqrtRatioAX96;
    }

    function getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
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
