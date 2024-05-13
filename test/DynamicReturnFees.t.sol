// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {LPFeeLibrary} from "../src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DynamicReturnFeeTestHook} from "../src/test/DynamicReturnFeeTestHook.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FullMath} from "../src/libraries/FullMath.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";

contract TestDynamicReturnFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicReturnFeeTestHook dynamicReturnFeesHook = DynamicReturnFeeTestHook(
        address(uint160(uint256(type(uint160).max) & clearAllHookPermisssionsMask | Hooks.BEFORE_SWAP_FLAG))
    );

    event Swap(
        PoolId indexed poolId,
        address sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    function setUp() public {
        DynamicReturnFeeTestHook impl = new DynamicReturnFeeTestHook();
        vm.etch(address(dynamicReturnFeesHook), address(impl).code);

        deployFreshManagerAndRouters();
        dynamicReturnFeesHook.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            IHooks(address(dynamicReturnFeesHook)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_dynamicReturnSwapFee(uint24 fee) public {
        dynamicReturnFeesHook.setFee(fee);

        int256 amountSpecified = -10000;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);

        // after swapping ~1:1, the amount out (amount1) should be approximately 0.30% less than the amount specified
        assertEq(result.amount0(), amountSpecified);

        if (fee > LPFeeLibrary.MAX_LP_FEE) {
            // if the fee is too large, the fee is not used
            assertApproxEqAbs(uint256(int256(result.amount1())), uint256(int256(-result.amount0())), 1 wei);
        } else {
            assertApproxEqAbs(
                uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - fee), 1e6), 1 wei
            );
        }
    }

    function test_returnDynamicSwapFee_beforeSwap_succeeds_gas() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicReturnFeesHook.setFee(123);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapLastCall("swap with return dynamic fee");

        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_initializeZeroSwapFee() public {
        key.tickSpacing = 30;
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function test_dynamicReturnSwapFee_notUsedIfPoolIsStaticFee() public {
        key.fee = 3000; // static fee
        dynamicReturnFeesHook.setFee(1000); // 0.10% fee is NOT used because the pool has a static fee

        initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(dynamicReturnFeesHook)), 3000, SQRT_PRICE_1_1, ZERO_BYTES
        );
        assertEq(_fetchPoolSwapFee(key), 3000);

        // despite returning a valid swap fee (1000), the static fee is used
        int256 amountSpecified = -10000;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);

        // after swapping ~1:1, the amount out (amount1) should be approximately 0.30% less than the amount specified
        assertEq(result.amount0(), amountSpecified);
        assertApproxEqAbs(
            uint256(int256(result.amount1())), FullMath.mulDiv(uint256(-amountSpecified), (1e6 - 3000), 1e6), 1 wei
        );
    }

    function test_dynamicReturnSwapFee_notUsedWithTooLargeFee() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicReturnFeesHook.setFee(1000001);

        // a large fee is not used
        int256 amountSpecified = -10000;
        BalanceDelta result = swap(key, true, amountSpecified, ZERO_BYTES);

        // after swapping ~1:1, the amount out (amount1) should be approximately 0.30% less than the amount specified
        assertEq(result.amount0(), amountSpecified);
        assertApproxEqAbs(uint256(int256(result.amount1())), uint256(int256(-result.amount0())), 1 wei);
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,,, swapFee) = manager.getSlot0(id);
    }
}
