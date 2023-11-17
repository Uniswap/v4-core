// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {FeeLibrary} from "../src/libraries/FeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IFees} from "../src/interfaces/IFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IDynamicFeeManager} from "././../src/interfaces/IDynamicFeeManager.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DynamicFeesTestHook} from "../src/test/DynamicFeesTestHook.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestDynamicFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicFeesTestHook dynamicFeesHook = DynamicFeesTestHook(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_MODIFY_POSITION_FLAG
                        & ~Hooks.AFTER_MODIFY_POSITION_FLAG & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG
                        & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    DynamicFeesTestHook dynamicFeesNoHook = DynamicFeesTestHook(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_MODIFY_POSITION_FLAG
                        & ~Hooks.AFTER_MODIFY_POSITION_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.AFTER_SWAP_FLAG
                        & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    function setUp() public {
        DynamicFeesTestHook impl = new DynamicFeesTestHook();
        vm.etch(address(dynamicFeesHook), address(impl).code);
        vm.etch(address(dynamicFeesNoHook), address(impl).code);

        deployFreshManagerAndRouters();
        dynamicFeesHook.setManager(IPoolManager(manager));
        dynamicFeesNoHook.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            IHooks(address(dynamicFeesHook)),
            FeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );
    }

    function testPoolInitializeFailsWithTooLargeFee() public {
        (Currency currency2, Currency currency3) = deployMintAndApprove2Currencies();
        key = PoolKey({
            currency0: currency2,
            currency1: currency3,
            fee: FeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: dynamicFeesHook,
            tickSpacing: 60
        });
        dynamicFeesHook.setFee(1000000);

        vm.expectRevert(IFees.FeeTooLarge.selector);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testUpdateFailsWithTooLargeFee() public {
        dynamicFeesHook.setFee(1000000);
        vm.expectRevert(IFees.FeeTooLarge.selector);
        manager.updateDynamicSwapFee(key);
    }

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

    function testSwapWorks() public {
        dynamicFeesHook.setFee(123);
        manager.updateDynamicSwapFee(key);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -98, 79228162514264329749955861424, 1e18, -1, 123);

        snapStart("swap with dynamic fee");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }

    function testCacheDynamicFeeAndSwap() public {
        dynamicFeesHook.setFee(123);
        manager.updateDynamicSwapFee(key);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -98, 79228162514264329749955861424, 1e18, -1, 456);
        bytes memory data = abi.encode(true, uint24(456));

        snapStart("update dynamic fee in before swap");
        swapRouter.swap(key, params, testSettings, data);
        snapEnd();
    }

    function testDynamicFeeAndBeforeSwapHook() public {
        dynamicFeesHook.setFee(123);
        manager.updateDynamicSwapFee(key);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -98, 79228162514264329749955861424, 1e18, -1, 123);
        bytes memory data = abi.encode(false, uint24(0));

        snapStart("before swap hook, already cached dynamic fee");
        swapRouter.swap(key, params, testSettings, data);
        snapEnd();
    }

    function testUpdateRevertsOnStaticFeePool() public {
        (key,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        vm.expectRevert(IFees.FeeNotDynamic.selector);
        manager.updateDynamicSwapFee(key);
    }

    function testDynamicFeesCacheNoOtherHooks() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, dynamicFeesNoHook, FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1, ZERO_BYTES
        );

        dynamicFeesNoHook.setFee(123);
        manager.updateDynamicSwapFee(key);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -98, 79228162514264329749955861424, 1e18, -1, 123);

        snapStart("cached dynamic fee, no hooks");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }
}
