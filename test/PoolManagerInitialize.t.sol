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
import {PoolId} from "../src/types/PoolId.sol";
import {LPFeeLibrary} from "../src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "../src/libraries/ProtocolFeeLibrary.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";

contract PoolManagerInitializeTest is Test, Deployers {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using ProtocolFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    event Initialize(
        PoolId indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        uninitializedKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            hooks: IHooks(Constants.ADDRESS_ZERO),
            tickSpacing: 60
        });
    }

    function test_fuzz_initialize(PoolKey memory key0, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // tested in Hooks.t.sol
        key0.hooks = IHooks(Constants.ADDRESS_ZERO);

        if (key0.tickSpacing > TickMath.MAX_TICK_SPACING) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector, key0.tickSpacing));
            manager.initialize(key0, sqrtPriceX96);
        } else if (key0.tickSpacing < TickMath.MIN_TICK_SPACING) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector, key0.tickSpacing));
            manager.initialize(key0, sqrtPriceX96);
        } else if (key0.currency0 >= key0.currency1) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPoolManager.CurrenciesOutOfOrderOrEqual.selector, key0.currency0, key0.currency1
                )
            );
            manager.initialize(key0, sqrtPriceX96);
        } else if (!key0.hooks.isValidHookAddress(key0.fee)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(key0.hooks)));
            manager.initialize(key0, sqrtPriceX96);
        } else if ((key0.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG) && (key0.fee > 1000000)) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, key0.fee));
            manager.initialize(key0, sqrtPriceX96);
        } else {
            int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
            vm.expectEmit(true, true, true, true);
            emit Initialize(
                key0.toId(), key0.currency0, key0.currency1, key0.fee, key0.tickSpacing, key0.hooks, sqrtPriceX96, tick
            );
            manager.initialize(key0, sqrtPriceX96);

            (uint160 slot0SqrtPriceX96,, uint24 slot0ProtocolFee,) = manager.getSlot0(key0.toId());
            assertEq(slot0SqrtPriceX96, sqrtPriceX96);
            assertEq(slot0ProtocolFee, 0);
        }
    }

    function test_initialize_forNativeTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        uninitializedKey.currency0 = CurrencyLibrary.ADDRESS_ZERO;

        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks,
            sqrtPriceX96,
            tick
        );
        manager.initialize(uninitializedKey, sqrtPriceX96);

        (uint160 slot0SqrtPriceX96, int24 slot0Tick, uint24 slot0ProtocolFee,) =
            manager.getSlot0(uninitializedKey.toId());
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
        assertEq(slot0ProtocolFee, 0);
        assertEq(slot0Tick, TickMath.getTickAtSqrtPrice(sqrtPriceX96));
    }

    function test_initialize_succeedsWithHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address payable mockAddr = payable(address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG)));
        address payable hookAddr = payable(Constants.ALL_HOOKS);

        vm.etch(hookAddr, vm.getDeployedCode("EmptyTestHooks.sol:EmptyTestHooks"));
        MockContract mockContract = new MockContract();
        vm.etch(mockAddr, address(mockContract).code);

        MockContract(mockAddr).setImplementation(hookAddr);

        uninitializedKey.hooks = IHooks(mockAddr);

        int24 tick = manager.initialize(uninitializedKey, sqrtPriceX96);
        (uint160 slot0SqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(slot0SqrtPriceX96, sqrtPriceX96, "sqrtPrice");

        bytes32 beforeSelector = MockHooks.beforeInitialize.selector;
        bytes memory beforeParams = abi.encode(address(this), uninitializedKey, sqrtPriceX96);

        bytes32 afterSelector = MockHooks.afterInitialize.selector;
        bytes memory afterParams = abi.encode(address(this), uninitializedKey, sqrtPriceX96, tick);

        assertEq(MockContract(mockAddr).timesCalledSelector(beforeSelector), 1, "beforeSelector count");
        assertTrue(MockContract(mockAddr).calledWithSelector(beforeSelector, beforeParams), "beforeSelector params");
        assertEq(MockContract(mockAddr).timesCalledSelector(afterSelector), 1, "afterSelector count");
        assertTrue(MockContract(mockAddr).calledWithSelector(afterSelector, afterParams), "afterSelector params");
    }

    function test_initialize_succeedsWithMaxTickSpacing(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        uninitializedKey.tickSpacing = TickMath.MAX_TICK_SPACING;

        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks,
            sqrtPriceX96,
            tick
        );

        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_succeedsWithEmptyHooks(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        address allHooksAddr = Constants.ALL_HOOKS;

        MockHooks impl = new MockHooks();
        vm.etch(allHooksAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(allHooksAddr);

        uninitializedKey.hooks = mockHooks;

        manager.initialize(uninitializedKey, sqrtPriceX96);
        (uint160 slot0SqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(slot0SqrtPriceX96, sqrtPriceX96);
    }

    function test_initialize_revertsWithIdenticalTokens(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // Both currencies are currency0
        uninitializedKey.currency1 = currency0;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.CurrenciesOutOfOrderOrEqual.selector,
                Currency.unwrap(currency0),
                Currency.unwrap(currency0)
            )
        );
        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_revertsWithSameTokenCombo(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        uninitializedKey.currency1 = currency0;
        uninitializedKey.currency0 = currency1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.CurrenciesOutOfOrderOrEqual.selector,
                Currency.unwrap(currency1),
                Currency.unwrap(currency0)
            )
        );
        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_revertsWhenPoolAlreadyInitialized(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        manager.initialize(uninitializedKey, sqrtPriceX96);
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        manager.initialize(uninitializedKey, sqrtPriceX96);
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
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1);

        // Fail at afterInitialize hook.
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1);
    }

    function test_initialize_succeedsWithCorrectSelectors() public {
        address hookAddr = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        uninitializedKey.hooks = mockHooks;

        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, mockHooks.beforeInitialize.selector);
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, mockHooks.afterInitialize.selector);

        int24 tick = TickMath.getTickAtSqrtPrice(SQRT_PRICE_1_1);

        vm.expectEmit(true, true, true, true);
        emit Initialize(
            uninitializedKey.toId(),
            uninitializedKey.currency0,
            uninitializedKey.currency1,
            uninitializedKey.fee,
            uninitializedKey.tickSpacing,
            uninitializedKey.hooks,
            SQRT_PRICE_1_1,
            tick
        );

        manager.initialize(uninitializedKey, SQRT_PRICE_1_1);
    }

    function test_initialize_failsIfTickSpaceTooLarge(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        uninitializedKey.tickSpacing = TickMath.MAX_TICK_SPACING + 1;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector, uninitializedKey.tickSpacing));
        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_failsIfTickSpaceZero(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        uninitializedKey.tickSpacing = 0;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector, uninitializedKey.tickSpacing));
        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_failsIfTickSpaceNeg(uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        uninitializedKey.tickSpacing = -1;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector, uninitializedKey.tickSpacing));
        manager.initialize(uninitializedKey, sqrtPriceX96);
    }

    function test_initialize_gas() public {
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1);
        vm.snapshotGasLastCall("initialize");
    }
}
