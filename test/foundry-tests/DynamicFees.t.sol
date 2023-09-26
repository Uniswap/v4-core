// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../../contracts/types/PoolId.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {FeeLibrary} from "../../contracts/libraries/FeeLibrary.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {IFees} from "../../contracts/interfaces/IFees.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {PoolKey} from "../../contracts/types/PoolKey.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IDynamicFeeManager} from "././../../contracts/interfaces/IDynamicFeeManager.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DynamicFeesTest} from "../../contracts/test/DynamicFeesTest.sol";

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

    function setUp() public {
        DynamicFeesTest impl = new DynamicFeesTest();
        vm.etch(address(dynamicFees), address(impl).code);
        vm.etch(address(dynamicFeesNoHook), address(impl).code);

        (manager, key,) =
            Deployers.createFreshPool(IHooks(address(dynamicFees)), FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1);
        dynamicFees.setManager(IPoolManager(manager));

        PoolId id2;
        (key2, id2) = Deployers.createPool(
            manager, IHooks(address(dynamicFeesNoHook)), FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1
        );
        dynamicFeesNoHook.setManager(IPoolManager(manager));

        swapRouter = new PoolSwapTest(manager);
    }

    function testPoolInitializeFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
        PoolKey memory key0 = Deployers.createKey(IHooks(address(dynamicFees)), FeeLibrary.DYNAMIC_FEE_FLAG);
        vm.expectRevert(IFees.FeeTooLarge.selector);
        manager.initialize(key0, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testSwapFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
        vm.expectRevert(IFees.FeeTooLarge.selector);
        manager.setDynamicFee(key);
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
        manager.setDynamicFee(key);
        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_1 + 1, 0, 0, 123);
        snapStart("swap with dynamic fee");
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
        snapEnd();
    }

    function testCacheDynamicFeeAndSwap() public {
        dynamicFees.setFee(123);
        manager.setDynamicFee(key);
        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_1 + 1, 0, 0, 456);
        snapStart("update dynamic fee in before swap");
        bytes memory data = abi.encode(true, uint24(456));
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1), PoolSwapTest.TestSettings(false, false), data
        );
        snapEnd();
    }

    function testDynamicFeeAndBeforeSwapHook() public {
        dynamicFees.setFee(123);
        manager.setDynamicFee(key);
        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_1 + 1, 0, 0, 123);
        snapStart("before swap hook, already cached dynamic fee");
        bytes memory data = abi.encode(false, uint24(0));
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1), PoolSwapTest.TestSettings(false, false), data
        );
        snapEnd();
    }

    function testDynamicFeesCacheNoOtherHooks() public {
        dynamicFeesNoHook.setFee(123);
        manager.setDynamicFee(key2);
        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key2.toId(), address(swapRouter), 0, 0, SQRT_RATIO_1_1 + 1, 0, 0, 123);
        snapStart("cached dynamic fee, no hooks");
        swapRouter.swap(
            key2,
            IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
        snapEnd();
    }
}
