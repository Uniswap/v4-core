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

contract DynamicFees is IDynamicFeeManager {
    uint24 internal fee;

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function getFee(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        public
        view
        returns (uint24)
    {
        return fee;
    }
}

contract TestDynamicFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicFees dynamicFees = DynamicFees(
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
    PoolSwapTest swapRouter;

    function setUp() public {
        DynamicFees impl = new DynamicFees();
        vm.etch(address(dynamicFees), address(impl).code);

        (manager, key,) =
            Deployers.createFreshPool(IHooks(address(dynamicFees)), FeeLibrary.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1);
        swapRouter = new PoolSwapTest(manager);
    }

    function testSwapFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
        vm.expectRevert(IFees.FeeTooLarge.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1),
            PoolSwapTest.TestSettings(false, false),
            ZERO_BYTES
        );
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
}
