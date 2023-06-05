pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {Position} from "../../contracts/libraries/Position.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {TickBitmap} from "../../contracts/libraries/TickBitmap.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";

contract PoolTest is Test {
    using Pool for Pool.State;

    Pool.State state;

    function testPoolInitialize(uint160 sqrtPriceX96, uint8 protocolFee, uint8 hookFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96, protocolFee, hookFee, protocolFee, hookFee);
        } else {
            state.initialize(sqrtPriceX96, protocolFee, hookFee, protocolFee, hookFee);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.protocolSwapFee, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function testModifyPosition(uint160 sqrtPriceX96, Pool.ModifyPositionParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing > 0);
        vm.assume(params.tickSpacing < 32768);

        testPoolInitialize(sqrtPriceX96, 0, 0);

        if (params.tickLower >= params.tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, params.tickLower, params.tickUpper));
        } else if (params.tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, params.tickLower));
        } else if (params.tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, params.tickUpper));
        } else if (params.liquidityDelta < 0) {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        } else if (params.liquidityDelta == 0) {
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        } else if (params.liquidityDelta > int128(Pool.tickSpacingToMaxLiquidityPerTick(params.tickSpacing))) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, params.tickLower));
        } else if (params.tickLower % params.tickSpacing != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickLower, params.tickSpacing)
            );
        } else if (params.tickUpper % params.tickSpacing != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickUpper, params.tickSpacing)
            );
        }

        params.owner = address(this);
        state.modifyPosition(params);
    }

    function testSwap(uint160 sqrtPriceX96, Pool.SwapParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing > 0);
        vm.assume(params.tickSpacing < 32768);
        vm.assume(params.fee < 1000000);

        testPoolInitialize(sqrtPriceX96, 0, 0);
        Pool.Slot0 memory slot0 = state.slot0;

        if (params.amountSpecified == 0) {
            vm.expectRevert(Pool.SwapAmountCannotBeZero.selector);
        } else if (params.zeroForOne) {
            if (params.sqrtPriceLimitX96 >= slot0.sqrtPriceX96) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        } else if (!params.zeroForOne) {
            if (params.sqrtPriceLimitX96 <= slot0.sqrtPriceX96) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        }

        state.swap(params);

        if (params.zeroForOne) {
            assertLe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        } else {
            assertGe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        }
    }
}
