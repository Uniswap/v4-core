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
import {DynamicFeesTest} from "../src/test/DynamicFeesTest.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestDynamicFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicFeesTest dynamicFees = DynamicFeesTest(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_MODIFY_POSITION_FLAG
                        & ~Hooks.AFTER_MODIFY_POSITION_FLAG & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG
                        & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    DynamicFeesTest dynamicFeesNoHook = DynamicFeesTest(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_MODIFY_POSITION_FLAG
                        & ~Hooks.AFTER_MODIFY_POSITION_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.AFTER_SWAP_FLAG
                        & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    PoolManager manager;
    PoolKey key;
    PoolKey key2;
    PoolSwapTest swapRouter;
    PoolModifyPositionTest modifyPositionRouter;

    function setUp() public {
        DynamicFeesTest impl = new DynamicFeesTest();
        vm.etch(address(dynamicFees), address(impl).code);
        vm.etch(address(dynamicFeesNoHook), address(impl).code);

        (manager, key,) =
            Deployers.createAndInitFreshPool(IHooks(address(dynamicFees)), FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1);
        dynamicFees.setManager(IPoolManager(manager));

        (key2,) = Deployers.createAndInitPool(
            manager, IHooks(address(dynamicFeesNoHook)), FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1
        );
        dynamicFeesNoHook.setManager(IPoolManager(manager));

        swapRouter = new PoolSwapTest(manager);
        modifyPositionRouter = new PoolModifyPositionTest(manager);

        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(key2.currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(key2.currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(swapRouter), 10 ether);
        MockERC20(Currency.unwrap(key2.currency0)).approve(address(swapRouter), 10 ether);
        MockERC20(Currency.unwrap(key2.currency1)).approve(address(swapRouter), 10 ether);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(key2.currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(key2.currency1)).approve(address(modifyPositionRouter), 10 ether);

        // add liquidity for the 2 new pools
        IPoolManager.ModifyPositionParams memory liqParams =
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});
        modifyPositionRouter.modifyPosition(key, liqParams, ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key2, liqParams, ZERO_BYTES);
    }

    function testPoolInitializeFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
        PoolKey memory key0 = Deployers.createKey(IHooks(address(dynamicFees)), FeeLibrary.DYNAMIC_FEE_FLAG);
        vm.expectRevert(IFees.FeeTooLarge.selector);
        manager.initialize(key0, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testUpdateFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
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
        dynamicFees.setFee(123);
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
        dynamicFees.setFee(123);
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
        dynamicFees.setFee(123);
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
        (PoolKey memory staticPoolKey,) = Deployers.createAndInitPool(manager, IHooks(address(0)), 3000, SQRT_RATIO_1_1);
        vm.expectRevert(IFees.FeeNotDynamic.selector);
        manager.updateDynamicSwapFee(staticPoolKey);
    }

    function testDynamicFeesCacheNoOtherHooks() public {
        dynamicFeesNoHook.setFee(123);
        manager.updateDynamicSwapFee(key2);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -99, 79228162514264329670727698910, 1e18, -1, 0);

        snapStart("cached dynamic fee, no hooks");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();
    }
}
