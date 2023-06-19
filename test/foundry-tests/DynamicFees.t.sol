// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Currency} from "../../contracts/libraries/CurrencyLibrary.sol";
import {IERC20Minimal} from "../../contracts/interfaces/external/IERC20Minimal.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {SqrtPriceMath} from "../../contracts/libraries/SqrtPriceMath.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IDynamicFeeManager} from "././../../contracts/interfaces/IDynamicFeeManager.sol";
import {Fees} from "./../../contracts/libraries/Fees.sol";

contract DynamicFees is IDynamicFeeManager {
    uint24 internal fee;

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function getFee(IPoolManager.PoolKey calldata) public view returns (uint24) {
        return fee;
    }
}

contract TestDynamicFees is Test, Deployers {
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
    IPoolManager.PoolKey key;
    PoolSwapTest swapRouter;

    function setUp() public {
        DynamicFees impl = new DynamicFees();
        vm.etch(address(dynamicFees), address(impl).code);

        (manager, key,) = Deployers.createFreshPool(IHooks(address(dynamicFees)), Fees.DYNAMIC_FEE_FLAG, SQRT_RATIO_1_1);
        swapRouter = new PoolSwapTest(manager);
    }

    function testSwapFailsWithTooLargeFee() public {
        dynamicFees.setFee(1000000);
        vm.expectRevert(IPoolManager.FeeTooLarge.selector);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1), PoolSwapTest.TestSettings(false, false)
        );
    }

    event Swap(
        bytes32 indexed poolId,
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
        emit Swap(PoolId.toId(key), address(swapRouter), 0, 0, SQRT_RATIO_1_1 + 1, 0, 0, 123);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 1, SQRT_RATIO_1_1 + 1), PoolSwapTest.TestSettings(false, false)
        );
    }
}
