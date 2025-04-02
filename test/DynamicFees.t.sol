// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {SwapParams} from "../src/types/PoolOperation.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {DynamicFeesTestHook} from "../src/test/DynamicFeesTestHook.sol";
import {Currency} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../src/types/BalanceDelta.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {CustomRevert} from "../src/libraries/CustomRevert.sol";
import {ProtocolFeeLibrary} from "../src/libraries/ProtocolFeeLibrary.sol";

contract TestDynamicFees is Test, Deployers {
    using StateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    DynamicFeesTestHook dynamicFeesHooks = DynamicFeesTestHook(
        address(
            uint160(
                uint256(type(uint160).max) & clearAllHookPermissionsMask | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_INITIALIZE_FLAG
            )
        )
    );

    DynamicFeesTestHook dynamicFeesNoHooks =
        DynamicFeesTestHook(address(uint160(uint256(type(uint160).max) & clearAllHookPermissionsMask)));

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

        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(dynamicFeesHooks)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
    }

    function test_updateDynamicLPFee_afterInitialize_failsWithTooLargeFee() public {
        key.tickSpacing = 30;
        uint24 fee = 1000001;
        dynamicFeesHooks.setFee(fee);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(dynamicFeesHooks),
                IHooks.afterInitialize.selector,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_initialize_initializesFeeTo0() public {
        key.hooks = dynamicFeesNoHooks;

        // this fee is not fetched as theres no afterInitialize hook
        dynamicFeesNoHooks.setFee(1000000);

        manager.initialize(key, SQRT_PRICE_1_1);
        assertEq(_fetchPoolLPFee(key), 0);
    }

    function test_updateDynamicLPFee_afterInitialize_initializesFee() public {
        key.tickSpacing = 30;
        dynamicFeesHooks.setFee(123);

        manager.initialize(key, SQRT_PRICE_1_1);
        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_updateDynamicLPFee_revertsIfCallerIsntHook() public {
        vm.expectRevert(IPoolManager.UnauthorizedDynamicLPFeeUpdate.selector);
        manager.updateDynamicLPFee(key, 123);
    }

    function test_updateDynamicLPFee_revertsIfPoolHasStaticFee() public {
        key.fee = 3000; // static fee
        dynamicFeesHooks.setFee(123);

        // afterInitialize will try to update the fee, and fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(dynamicFeesHooks),
                IHooks.afterInitialize.selector,
                abi.encodeWithSelector(IPoolManager.UnauthorizedDynamicLPFeeUpdate.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_updateDynamicLPFee_beforeSwap_failsWithTooLargeFee() public {
        assertEq(_fetchPoolLPFee(key), 0);

        uint24 fee = 1000001;
        dynamicFeesHooks.setFee(1000001);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(dynamicFeesHooks),
                IHooks.beforeSwap.selector,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_updateDynamicLPFee_beforeSwap_succeeds_gas() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(123);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("update dynamic fee in before swap");

        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_swap_100PercentLPFee_AmountIn_NoProtocol() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 0, SQRT_PRICE_1_1, 1e18, -1, 1000000);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 1000000);
    }

    function test_swap_50PercentLPFee_AmountIn_NoProtocol() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(500000);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 49, 79228162514264333632135824623, 1e18, -1, 500000);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 500000);
    }

    function test_swap_50PercentLPFee_AmountOut_NoProtocol() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(500000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -202, 100, 79228162514264329670727698909, 1e18, -1, 500000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 500000);
    }

    function test_swap_revertsWith_InvalidFeeForExactOut_whenFeeIsMax() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_99PercentFee_AmountOut_WithProtocol() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(999999);

        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_100PercentFee_AmountIn_WithProtocol() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);

        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -1000, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -1000, 0, SQRT_PRICE_1_1, 1e18, -1, 1000000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 expectedProtocolFee = uint256(-params.amountSpecified) * 1000 / 1e6;
        assertEq(manager.protocolFeesAccrued(currency0), expectedProtocolFee);
    }

    function test_emitsSwapFee() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(123);

        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 1123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_fuzz_ProtocolAndLPFee(uint24 lpFee, uint16 protocolFee0, uint16 protocolFee1, int256 amountSpecified)
        public
    {
        assertEq(_fetchPoolLPFee(key), 0);

        lpFee = uint16(bound(lpFee, 0, 1000000));
        protocolFee0 = uint16(bound(protocolFee0, 0, 1000));
        protocolFee1 = uint16(bound(protocolFee1, 0, 1000));
        vm.assume(amountSpecified != 0);

        uint24 protocolFee = (uint24(protocolFee1) << 12) | uint24(protocolFee0);
        dynamicFeesHooks.setFee(lpFee);

        vm.prank(feeController);
        manager.setProtocolFee(key, protocolFee);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        BalanceDelta delta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint24 swapFee = uint16(protocolFee).calculateSwapFee(lpFee);

        uint256 expectedProtocolFee = uint256(uint128(-delta.amount0())) * protocolFee0 / 1e6;
        if (lpFee == 0) {
            assertEq(protocolFee0, swapFee);
            if (((uint256(uint128(-delta.amount0())) * protocolFee0) % 1e6) != 0) expectedProtocolFee++;
        }

        assertEq(manager.protocolFeesAccrued(currency0), expectedProtocolFee);
    }

    function test_swap_withDynamicFee_gas() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, dynamicFeesNoHooks, LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        assertEq(_fetchPoolLPFee(key), 0);
        dynamicFeesNoHooks.forcePoolFeeUpdate(key, 123);
        assertEq(_fetchPoolLPFee(key), 123);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap with dynamic fee");
    }

    function _fetchPoolLPFee(PoolKey memory _key) internal view returns (uint256 lpFee) {
        PoolId id = _key.toId();
        (,,, lpFee) = manager.getSlot0(id);
    }
}
