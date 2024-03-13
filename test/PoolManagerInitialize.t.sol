// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Constants} from "./utils/Constants.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockHooks} from "../src/test/MockHooks.sol";
import {MockContract} from "../src/test/MockContract.sol";
import {EmptyTestHooks} from "../src/test/EmptyTestHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {SwapFeeLibrary} from "../src/libraries/SwapFeeLibrary.sol";
import {ProtocolFeeControllerTest} from "../src/test/ProtocolFeeControllerTest.sol";
import {IProtocolFeeController} from "../src/interfaces/IProtocolFeeController.sol";

contract PoolManagerInitializeTest is Test, Deployers, GasSnapshot {
    using Hooks for IHooks;
    using PoolIdLibrary for PoolKey;
    using SwapFeeLibrary for uint24;

    event Initialize(
        PoolId indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        uninitializedKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(Constants.ADDRESS_ZERO),
            tickSpacing: 60
        });
    }

    function test_initialize(PoolKey memory key0, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        // tested in Hooks.t.sol
        key0.hooks = IHooks(Constants.ADDRESS_ZERO);

        if (key0.tickSpacing > manager.MAX_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);
        } else if (key0.tickSpacing < manager.MIN_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);
        } else if (key0.currency0 >= key0.currency1) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrenciesOutOfOrderOrEqual.selector));
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);
        } else if (!key0.hooks.isValidHookAddress(key0.fee)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(key0.hooks)));
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);
        } else if (
            (key.fee & SwapFeeLibrary.DYNAMIC_FEE_FLAG == 0) && (key0.fee & SwapFeeLibrary.STATIC_FEE_MASK >= 1000000)
        ) {
            vm.expectRevert(abi.encodeWithSelector(SwapFeeLibrary.FeeTooLarge.selector));
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);
        } else {
            vm.expectEmit(true, true, true, true);
            emit Initialize(key0.toId(), key0.currency0, key0.currency1, key0.fee, key0.tickSpacing, key0.hooks);
            manager.initialize(key0, sqrtPriceX96, ZERO_BYTES);

            (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
            assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(slot0.protocolFee, 0);
        }
    }

    function test_initialize_forNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));
        uninitializedKey.currency0 = CurrencyLibrary.NATIVE;

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
        assertEq(slot0.protocolFee, 0);
        assertEq(slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
    }

    function test_initialize_succeedsWithHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        address payable hookAddr = payable(Constants.MOCK_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        uninitializedKey.hooks = IHooks(mockAddr);

        int24 tick = manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96, "sqrtPrice");

        bytes32 beforeSelector = MockHooks.beforeInitialize.selector;
        bytes memory beforeParams = abi.encode(address(this), uninitializedKey, sqrtPriceX96, ZERO_BYTES);

        bytes32 afterSelector = MockHooks.afterInitialize.selector;
        bytes memory afterParams = abi.encode(address(this), uninitializedKey, sqrtPriceX96, tick, ZERO_BYTES);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1, "beforeSelector count");
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams), "beforeSelector params");
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1, "afterSelector count");
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams), "afterSelector params");
    }

    function test_initialize_succeedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        uninitializedKey.tickSpacing = manager.MAX_TICK_SPACING();

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );

        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_succeedsWithEmptyHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        address hookEmptyAddr = Constants.EMPTY_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(hookEmptyAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookEmptyAddr);

        uninitializedKey.hooks = mockHooks;

        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.sqrtPriceX96, sqrtPriceX96);
    }

    function test_initialize_revertsWithIdenticalTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        // Both currencies are currency0
        uninitializedKey.currency1 = currency0;

        vm.expectRevert(IPoolManager.CurrenciesOutOfOrderOrEqual.selector);
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_revertsWithSameTokenCombo(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        uninitializedKey.currency1 = currency0;
        uninitializedKey.currency0 = currency1;

        vm.expectRevert(IPoolManager.CurrenciesOutOfOrderOrEqual.selector);
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_fetchFeeWhenController(uint16 protocolFee) public {
        manager.setProtocolFeeController(feeController);
        feeController.setSwapFeeForPool(uninitializedKey.toId(), protocolFee);

        uint8 fee0 = uint8(protocolFee >> 8);
        uint8 fee1 = uint8(protocolFee % 256);

        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);

        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.sqrtPriceX96, SQRT_RATIO_1_1);
        if ((0 < fee0 && fee0 < 4) || (0 < fee1 && fee1 < 4)) {
            assertEq(slot0.protocolFee, 0);
        } else {
            assertEq(slot0.protocolFee, protocolFee);
        }
    }

    function test_initialize_revertsWhenPoolAlreadyInitialized(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsWithIncorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        uninitializedKey.hooks = mockHooks;

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));

        // Fails at beforeInitialize hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);

        // Fail at afterInitialize hook.
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_initialize_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        uninitializedKey.hooks = mockHooks;

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, mockHooks.afterInitialize.selector);

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );

        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        uninitializedKey.tickSpacing = manager.MAX_TICK_SPACING() + 1;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        uninitializedKey.tickSpacing = 0;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_failsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        uninitializedKey.tickSpacing = -1;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
    }

    function test_initialize_succeedsWithOutOfBoundsFeeController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        manager.setProtocolFeeController(outOfBoundsFeeController);
        // expect initialize to succeed even though the controller reverts
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        // protocol fees should default to 0
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.protocolFee, 0);
        // call to setProtocolFee should also revert
        vm.expectRevert(IProtocolFees.ProtocolFeeControllerCallFailedOrInvalidResult.selector);
        manager.setProtocolFee(uninitializedKey);
    }

    function test_initialize_succeedsWithRevertingFeeController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        manager.setProtocolFeeController(revertingFeeController);
        // expect initialize to succeed even though the controller reverts
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        // protocol fees should default to 0
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.protocolFee, 0);
    }

    function test_initialize_succeedsWithOverflowFeeController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        manager.setProtocolFeeController(overflowFeeController);
        // expect initialize to succeed
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        // protocol fees should default to 0
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.protocolFee, 0);
    }

    function test_initialize_succeedsWithWrongReturnSizeFeeController(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO - 1));

        manager.setProtocolFeeController(invalidReturnSizeFeeController);
        // expect initialize to succeed
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks
        );
        manager.initialize(uninitializedKey, sqrtPriceX96, ZERO_BYTES);
        // protocol fees should default to 0
        (Pool.Slot0 memory slot0,,,) = manager.pools(uninitializedKey.toId());
        assertEq(slot0.protocolFee, 0);
    }

    function test_initialize_gas() public {
        snapStart("initialize");
        manager.initialize(uninitializedKey, SQRT_RATIO_1_1, ZERO_BYTES);
        snapEnd();
    }
}
