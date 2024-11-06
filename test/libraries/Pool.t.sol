// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../../src/libraries/Pool.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {Position} from "../../src/libraries/Position.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {TickBitmap} from "../../src/libraries/TickBitmap.sol";
import {LiquidityAmounts} from "../../test/utils/LiquidityAmounts.sol";
import {Constants} from "../../test/utils/Constants.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {Slot0} from "../../src/types/Slot0.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";
import {ProtocolFeeLibrary} from "../../src/libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";

contract PoolTest is Test {
    using Pool for Pool.State;
    using LPFeeLibrary for uint24;
    using ProtocolFeeLibrary for *;

    Pool.State state;

    uint24 constant MAX_PROTOCOL_FEE = ProtocolFeeLibrary.MAX_PROTOCOL_FEE; // 0.1%
    uint24 constant MAX_LP_FEE = LPFeeLibrary.MAX_LP_FEE; // 100%

    function test_pool_initialize(uint160 sqrtPriceX96, uint24 swapFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            vm.expectRevert(abi.encodeWithSelector(TickMath.InvalidSqrtPrice.selector, sqrtPriceX96));
            state.initialize(sqrtPriceX96, swapFee);
        } else {
            state.initialize(sqrtPriceX96, swapFee);
            assertEq(state.slot0.sqrtPriceX96(), sqrtPriceX96);
            assertEq(state.slot0.protocolFee(), 0);
            assertEq(state.slot0.tick(), TickMath.getTickAtSqrtPrice(sqrtPriceX96));
            assertLt(state.slot0.tick(), TickMath.MAX_TICK);
            assertGt(state.slot0.tick(), TickMath.MIN_TICK - 1);
        }
    }

    function test_modifyLiquidity(uint160 sqrtPriceX96, uint24 lpFee, Pool.ModifyLiquidityParams memory params)
        public
    {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        test_pool_initialize(sqrtPriceX96, lpFee);

        if (params.tickLower >= params.tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, params.tickLower, params.tickUpper));
        } else if (params.tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, params.tickLower));
        } else if (params.tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, params.tickUpper));
        } else if (params.liquidityDelta < 0) {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
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
                TickMath.getSqrtPriceAtTick(params.tickLower),
                TickMath.getSqrtPriceAtTick(params.tickUpper),
                uint128(params.liquidityDelta)
            );

            if ((amount0 > maxInt128InTypeU256) || (amount1 > maxInt128InTypeU256)) {
                vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
            }
        }

        params.owner = address(this);
        state.modifyLiquidity(params);
    }

    function test_fuzz_swap(
        uint160 sqrtPriceX96,
        uint24 lpFee,
        uint16 protocolFee0,
        uint16 protocolFee1,
        Pool.SwapParams memory params
    ) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        lpFee = uint24(bound(lpFee, 0, MAX_LP_FEE));
        protocolFee0 = uint16(bound(protocolFee0, 0, MAX_PROTOCOL_FEE));
        protocolFee1 = uint16(bound(protocolFee1, 0, MAX_PROTOCOL_FEE));
        uint24 protocolFee = protocolFee1 << 12 | protocolFee0;

        // initialize and add liquidity
        test_modifyLiquidity(
            sqrtPriceX96,
            lpFee,
            Pool.ModifyLiquidityParams({
                owner: address(this),
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e18,
                tickSpacing: 60,
                salt: 0
            })
        );
        Slot0 slot0 = state.slot0;

        assertEq(slot0.protocolFee(), 0);
        slot0 = slot0.setProtocolFee(protocolFee);
        assertEq(slot0.protocolFee(), protocolFee);
        state.slot0 = slot0;

        uint16 expectedProtocolFee = params.zeroForOne ? protocolFee0 : protocolFee1;

        uint24 _lpFee = params.lpFeeOverride.isOverride() ? params.lpFeeOverride.removeOverrideFlag() : lpFee;
        uint24 swapFee = expectedProtocolFee == 0 ? _lpFee : expectedProtocolFee.calculateSwapFee(_lpFee);

        if (params.amountSpecified >= 0 && swapFee == MAX_LP_FEE) {
            vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
            state.swap(params);
        } else if (!_lpFee.isValid()) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, _lpFee));
            state.swap(params);
        } else if (params.zeroForOne && params.amountSpecified != 0) {
            if (params.sqrtPriceLimitX96 >= slot0.sqrtPriceX96()) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
                    )
                );
                state.swap(params);
            } else if (params.sqrtPriceLimitX96 < TickMath.MIN_SQRT_PRICE) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
                state.swap(params);
            }
        } else if (!params.zeroForOne && params.amountSpecified != 0) {
            if (params.sqrtPriceLimitX96 <= slot0.sqrtPriceX96()) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
                    )
                );
                state.swap(params);
            } else if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_PRICE) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
                state.swap(params);
            }
        } else {
            uint160 sqrtPriceBefore = state.slot0.sqrtPriceX96();
            state.swap(params);

            if (params.amountSpecified == 0) {
                assertEq(sqrtPriceBefore, state.slot0.sqrtPriceX96(), "amountSpecified == 0");
            } else if (params.zeroForOne) {
                assertGe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "zeroForOne");
            } else {
                assertLe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "oneForZero");
            }
        }
    }

    function test_fuzz_tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) public pure {
        tickSpacing = int24(bound(tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        // v3 math
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        // assert that the result is the same as the v3 math or lower
        assertGe(type(uint128).max / numTicks, Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing));
    }
}
