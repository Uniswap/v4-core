// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {IProtocolFeeController} from "../../contracts/interfaces/IProtocolFeeController.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/libraries/CurrencyLibrary.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {MockHooksSimple} from "../../contracts/test/MockHooksSimple.sol";
import {MockContract} from "../../contracts/test/MockContract.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../../contracts/test/PoolLockTest.sol";
import {ProtocolFeeControllerTest} from "../../contracts/test/ProtocolFeeControllerTest.sol";
import {EmptyTestHooks} from "../../contracts/test/TestHooksImpl.sol";

contract PoolManagerTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using Pool for Pool.State;

    event LockAcquired(uint256 id);
    event Initialize(
        bytes32 indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    event ModifyPosition(
        bytes32 indexed poolId, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );

    Pool.State state;
    PoolManager manager;
    PoolDonateTest donateRouter;
    PoolModifyPositionTest modifyPositionRouter;
    PoolLockTest lockTest;
    ProtocolFeeControllerTest feeTest;

    address ADDRESS_ZERO = address(0);
    address EMPTY_HOOKS = address(0xf000000000000000000000000000000000000000);

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();
        donateRouter = new PoolDonateTest(manager);
        modifyPositionRouter = new PoolModifyPositionTest(manager);
        lockTest = new PoolLockTest(manager);
        feeTest = new ProtocolFeeControllerTest();

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 1 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 1 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(donateRouter), 1 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(donateRouter), 1 ether);
    }

    function testPoolManagerInitialize(IPoolManager.PoolKey memory key, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        // tested in Hooks.t.sol
        key.hooks = IHooks(address(0));

        if (key.fee >= 1000000 && key.fee != Hooks.DYNAMIC_FEE) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.FeeTooLarge.selector));
            manager.initialize(key, sqrtPriceX96);
        } else if (key.tickSpacing > manager.MAX_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
            manager.initialize(key, sqrtPriceX96);
        } else if (key.tickSpacing < manager.MIN_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
            manager.initialize(key, sqrtPriceX96);
        } else if (!key.hooks.isValidHookAddress(key.fee)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(key.hooks)));
            manager.initialize(key, sqrtPriceX96);
        } else {
            vm.expectEmit(true, true, true, true);
            emit Initialize(PoolId.toId(key), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
            manager.initialize(key, sqrtPriceX96);

            (Pool.Slot0 memory slot0,,,) = manager.pools(PoolId.toId(key));
            assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(slot0.protocolFee, 0);
        }
    }

    function testPoolManagerInitializeForNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: Currency.wrap(address(0)),
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        vm.expectEmit(true, true, true, true);
        emit Initialize(PoolId.toId(key), key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
        manager.initialize(key, sqrtPriceX96);

        (Pool.Slot0 memory slot0,,,) = manager.pools(PoolId.toId(key));
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolFee, 0);
    }

    function testPoolManagerInitializeSucceedsWithHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: mockHooks,
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);
        (Pool.Slot0 memory slot0,,,) = manager.pools(PoolId.toId(key));
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
    }

    function testPoolManagerInitializeSucceedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: manager.MAX_TICK_SPACING()
        });

        manager.initialize(key, sqrtPriceX96);
    }

    function testPoolManagerInitializeFailsIfNoHookSelector(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address hookEmptyAddr = EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: mockHooks,
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);
        (Pool.Slot0 memory slot0,,,) = manager.pools(PoolId.toId(key));
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
    }

    function testPoolManagerInitializeFailsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: manager.MAX_TICK_SPACING() + 1
        });

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
        manager.initialize(key, sqrtPriceX96);
    }

    function testPoolManagerInitializeFailsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: 0
        });

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96);
    }

    function testPoolManagerInitializeFailsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: -1
        });

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(key, sqrtPriceX96);
    }

    function testPoolManagerFetchFeeWhenController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        assertEq(address(manager.protocolFeeController()), address(0));
        manager.setProtocolFeeController(feeTest);
        assertEq(address(manager.protocolFeeController()), address(feeTest));

        uint8 poolProtocolFee = 4;

        feeTest.setFeeForPool(PoolId.toId(key), poolProtocolFee);

        manager.initialize(key, sqrtPriceX96);

        (Pool.Slot0 memory slot0,,,) = manager.pools(PoolId.toId(key));
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolFee, poolProtocolFee);
    }

    function testGasPoolManagerInitialize(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        snapStart("initialize");
        manager.initialize(key, sqrtPriceX96);
        snapEnd();
    }

    function testMintFailsIfNotInitialized() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });
        vm.expectRevert();
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
    }

    function testMintSucceedsIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);
        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(PoolId.toId(key), address(modifyPositionRouter), 0, 60, 100);

        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
    }

    function testMintSucceedsForNativeTokensIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);
        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(PoolId.toId(key), address(modifyPositionRouter), 0, 60, 100);

        modifyPositionRouter.modifyPosition{value: 100}(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
    }

    function testMintSucceedsWithHooksIfInitialized(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address payable hookAddr =
            payable(address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG)));

        MockHooksSimple hook = new MockHooksSimple();
        MockContract mockContract = new MockContract();
        vm.etch(hookAddr, address(mockContract).code);

        MockContract(hookAddr).setImplementation(address(hook));

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 60,
            hooks: IHooks(hookAddr),
            tickSpacing: 60
        });

        IPoolManager.ModifyPositionParams memory params =
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100});

        manager.initialize(key, sqrtPriceX96);

        IPoolManager.BalanceDelta memory balanceDelta = modifyPositionRouter.modifyPosition(key, params);

        bytes32 beforeSelector = MockHooks.beforeModifyPosition.selector;
        assertEq(MockContract(hookAddr).timesCalledSelector(beforeSelector), 1);

        bytes memory beforeParams = abi.encode(address(modifyPositionRouter), key, params);

        assertTrue(MockContract(hookAddr).calledWithSelector(beforeSelector, beforeParams));

        bytes32 afterSelector = MockHooks.afterModifyPosition.selector;
        assertEq(MockContract(hookAddr).timesCalledSelector(afterSelector), 1);

        bytes memory afterParams = abi.encode(address(modifyPositionRouter), key, params, balanceDelta);

        assertTrue(MockContract(hookAddr).calledWithSelector(afterSelector, afterParams));

        assertEq(MockContract(hookAddr).timesCalledSelector(MockHooks.beforeSwap.selector), 0);
        assertEq(MockContract(hookAddr).timesCalledSelector(MockHooks.afterSwap.selector), 0);
    }

    function testGasMint(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);

        snapStart("mint");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
        snapEnd();
    }

    function testGasMintWithNative(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);

        snapStart("mint with native token");
        modifyPositionRouter.modifyPosition{value: 100}(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
        snapEnd();
    }

    function testGasMintWithHooks(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        address hookEmptyAddr = EMPTY_HOOKS;
        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            tickSpacing: 60
        });

        manager.initialize(key, sqrtPriceX96);

        snapStart("mint with empty hook");
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 100})
        );
        snapEnd();
    }

    function testDonateFailsIfNotInitialized() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    function testDonateFailsIfNoLiquidity(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, sqrtPriceX96);
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    // test successful donation if pool has liquidity
    function testDonateSucceedsWhenPoolHasLiquidity() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);
        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200);
        snapEnd();

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(PoolId.toId(key));
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateSucceedsForNativeTokensWhenPoolHasLiquidity() public {
        vm.deal(address(this), 1 ether);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition{value: 1}(key, params);
        donateRouter.donate{value: 100}(key, 100, 200);

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(PoolId.toId(key));
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateSucceedsWithBeforeAndAfterHooks() public {
        address hookAddr = address(uint160(Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

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

        // Succeeds.
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);
        donateRouter.donate(key, 100, 200);
    }

    function testGasDonateOneToken() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);

        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0);
        snapEnd();
    }

    function testNoOpLockIsOk() public {
        snapStart("gas overhead of no-op lock");
        lockTest.lock();
        snapEnd();
    }

    function testLockEmitsCorrectId() public {
        vm.expectEmit(false, false, false, true);
        emit LockAcquired(0);
        lockTest.lock();
    }

    receive() external payable {}
}
