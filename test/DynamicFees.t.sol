// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {SwapFeeLibrary} from "../src/libraries/SwapFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DynamicFeesTestHook} from "../src/test/DynamicFeesTestHook.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestDynamicFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicFeesTestHook dynamicFeesHooks = DynamicFeesTestHook(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG
                        & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_SWAP_FLAG
                        & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    DynamicFeesTestHook dynamicFeesNoHooks = DynamicFeesTestHook(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                        & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                        & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.AFTER_SWAP_FLAG
                        & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                )
        )
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

    function setUp() public {
        DynamicFeesTestHook impl = new DynamicFeesTestHook();
        vm.etch(address(dynamicFeesHooks), address(impl).code);
        vm.etch(address(dynamicFeesNoHooks), address(impl).code);

        deployFreshManagerAndRouters();
        dynamicFeesHooks.setManager(IPoolManager(manager));
        dynamicFeesNoHooks.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            IHooks(address(dynamicFeesHooks)),
            SwapFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );
    }

    function test_updateDynamicSwapFee_afterInitialize_failsWithTooLargeFee() public {
        key.tickSpacing = 30;
        dynamicFeesHooks.setFee(1000000);

        vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_initialize_initializesFeeTo0() public {
        key.hooks = dynamicFeesNoHooks;

        // this fee is not fetched as theres no afterInitialize hook
        dynamicFeesNoHooks.setFee(1000000);

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_updateDynamicSwapFee_afterInitialize_initializesFee() public {
        key.tickSpacing = 30;
        dynamicFeesHooks.setFee(123);

        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
        assertEq(_fetchPoolSwapFee(key), 123);
    }

    function test_updateDynamicSwapFee_revertsIfCallerIsntHook() public {
        vm.expectRevert(IPoolManager.UnauthorizedDynamicSwapFeeUpdate.selector);
        manager.updateDynamicSwapFee(key, 123);
    }

    function test_updateDynamicSwapFee_revertsIfPoolHasStaticFee() public {
        key.fee = 3000; // static fee
        dynamicFeesHooks.setFee(123);

        // afterInitialize will try to update the fee, and fail
        vm.expectRevert(IPoolManager.UnauthorizedDynamicSwapFeeUpdate.selector);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_updateDynamicSwapFee_beforeSwap_failsWithTooLargeFee() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicFeesHooks.setFee(1000000);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_updateDynamicSwapFee_beforeSwap_succeeds_gas() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicFeesHooks.setFee(123);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        snapStart("update dynamic fee in before swap");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        assertEq(_fetchPoolSwapFee(key), 123);
    }

    function test_swap_withDynamicFee_gas() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, dynamicFeesNoHooks, SwapFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1, ZERO_BYTES
        );

        assertEq(_fetchPoolSwapFee(key), 0);
        dynamicFeesNoHooks.forcePoolFeeUpdate(key, 123);
        assertEq(_fetchPoolSwapFee(key), 123);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        snapStart("swap with dynamic fee");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,,, swapFee) = manager.getSlot0(id);
    }
}
