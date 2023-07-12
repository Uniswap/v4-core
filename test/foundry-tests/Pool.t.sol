pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {Position} from "../../contracts/libraries/Position.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {TickBitmap} from "../../contracts/libraries/TickBitmap.sol";
import {UQ64x96} from "../../contracts/libraries/FixedPoint96.sol";

contract PoolTest is Test {
    using Pool for Pool.State;

    Pool.State state;

    function testPoolInitialize(UQ64x96 sqrtPrice, uint8 protocolFee, uint8 hookFee) public {
        if (sqrtPrice < TickMath.MIN_SQRT_RATIO || sqrtPrice >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPrice, protocolFee, hookFee, protocolFee, hookFee);
        } else {
            state.initialize(sqrtPrice, protocolFee, hookFee, protocolFee, hookFee);
            assertEq(UQ64x96.unwrap(state.slot0.sqrtPrice), UQ64x96.unwrap(sqrtPrice));
            assertEq(state.slot0.protocolSwapFee, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPrice));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function testModifyPosition(UQ64x96 sqrtPrice, Pool.ModifyPositionParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing > 0);
        vm.assume(params.tickSpacing < 32768);

        testPoolInitialize(sqrtPrice, 0, 0);

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

    function testSwap(UQ64x96 sqrtPrice, Pool.SwapParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing > 0);
        vm.assume(params.tickSpacing < 32768);
        vm.assume(params.fee < 1000000);

        testPoolInitialize(sqrtPrice, 0, 0);
        Pool.Slot0 memory slot0 = state.slot0;

        if (params.amountSpecified == 0) {
            vm.expectRevert(Pool.SwapAmountCannotBeZero.selector);
        } else if (params.zeroForOne) {
            if (params.sqrtPriceLimit >= slot0.sqrtPrice) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPrice, params.sqrtPriceLimit
                    )
                );
            } else if (params.sqrtPriceLimit <= TickMath.MIN_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimit));
            }
        } else if (!params.zeroForOne) {
            if (params.sqrtPriceLimit <= slot0.sqrtPrice) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPrice, params.sqrtPriceLimit
                    )
                );
            } else if (params.sqrtPriceLimit >= TickMath.MAX_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimit));
            }
        }

        state.swap(params);

        if (params.zeroForOne) {
            assertLe(UQ64x96.unwrap(state.slot0.sqrtPrice), UQ64x96.unwrap(params.sqrtPriceLimit));
        } else {
            assertGe(UQ64x96.unwrap(state.slot0.sqrtPrice), UQ64x96.unwrap(params.sqrtPriceLimit));
        }
    }
}
