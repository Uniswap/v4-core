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
import {Currency} from "../../contracts/types/Currency.sol";
import {PoolKey} from "../../contracts/types/PoolKey.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IDynamicFeeManager} from "././../../contracts/interfaces/IDynamicFeeManager.sol";
import {Fees} from "./../../contracts/Fees.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "../../contracts/types/BalanceDelta.sol";

contract DynamicFees is IHooks, IDynamicFeeManager {
    uint24 internal fee;
    IPoolManager manager;

    constructor() {}

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function getFee(address, PoolKey calldata) public view returns (uint24) {
        return fee;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4) {
        // updates the dynamic fee in the pool if update is true
        bool _update;
        uint24 _fee;

        if (hookData.length > 0) {
            (_update, _fee) = abi.decode(hookData, (bool, uint24));
        }
        if (_update == true) {
            fee = _fee;

            manager.setDynamicFee(key);
        }
        return IHooks.beforeSwap.selector;
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }

    function beforeModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }

    function afterModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta,
        bytes calldata
    ) external view override returns (bytes4) {
        revert("not implemented");
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        revert("not implemented");
    }
}

contract TestDynamicFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicFees dynamicFees = DynamicFees(
        address(
            uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                & uint160(
                    ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_MODIFY_POSITION_FLAG
                        & ~Hooks.AFTER_MODIFY_POSITION_FLAG & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG
                        & ~Hooks.AFTER_DONATE_FLAG
                )
        )
    );

    DynamicFees dynamicFeesNoHook = DynamicFees(
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
        DynamicFees impl = new DynamicFees();
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
