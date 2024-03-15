// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {Position} from "../src/libraries/Position.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {TickBitmap} from "../src/libraries/TickBitmap.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";
import {Constants} from "./utils/Constants.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";

contract PoolTest is Test {
    using Pool for Pool.State;

    Pool.State state;

    function testPoolInitialize(uint160 sqrtPriceX96, uint16 protocolFee, uint24 dynamicFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96, protocolFee, dynamicFee);
        } else {
            state.initialize(sqrtPriceX96, protocolFee, dynamicFee);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.protocolFee, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function testModifyPosition(uint160 sqrtPriceX96, Pool.ModifyPositionParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

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
        } else {
            // We need the assumptions above to calculate this
            uint256 maxInt128InTypeU256 = uint256(uint128(Constants.MAX_UINT128));
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickLower),
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                uint128(params.liquidityDelta)
            );

            if ((amount0 > maxInt128InTypeU256) || (amount1 > maxInt128InTypeU256)) {
                vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
            }
        }

        params.owner = address(this);
        state.modifyLiquidity(params);
    }

    function testSwap(uint160 sqrtPriceX96, uint24 swapFee, Pool.SwapParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        swapFee = uint24(bound(swapFee, 0, 999999));

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
