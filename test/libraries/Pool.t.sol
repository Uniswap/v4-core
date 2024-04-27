// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "src/libraries/Pool.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Position} from "src/libraries/Position.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {TickBitmap} from "src/libraries/TickBitmap.sol";
import {LiquidityAmounts} from "test/utils/LiquidityAmounts.sol";
import {Constants} from "test/utils/Constants.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";

contract PoolTest is Test {
    using Pool for Pool.State;

    Pool.State state;

    uint24 constant MAX_PROTOCOL_FEE = ProtocolFeeLibrary.MAX_PROTOCOL_FEE; // 0.1%
    uint24 constant MAX_LP_FEE = LPFeeLibrary.MAX_LP_FEE; // 100%

    function testPoolInitialize(uint160 sqrtPriceX96, uint24 protocolFee, uint24 dynamicFee) public {
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

    function testModifyLiquidity(
        uint160 sqrtPriceX96,
        uint24 protocolFee,
        uint24 lpFee,
        Pool.ModifyLiquidityParams memory params
    ) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        testPoolInitialize(sqrtPriceX96, protocolFee, lpFee);

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

    function testSwap_edgeCase() public {
        // [FAIL. Reason: InvalidFeeForExactOut(); counterexample: calldata=0x0239f80e000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000047380000000000000000000000000000000000000000000000000000000000004002ffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8010240000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000feff00000000000000000000000000000000000000000000000000ffffffffffffff
        // args=[9223372036854775808 [9.223e18], 1000000 [1e6], 18232 [1.823e4], 16386 [1.638e4], SwapParams({ tickSpacing: -8384476 [-8.384e6], zeroForOne: true, amountSpecified: 65279 [6.527e4], sqrtPriceLimitX96: 72057594037927935 [7.205e16] })]] testSwap(uint160,uint24,uint16,uint16,(int24,bool,int256,uint160)) (runs: 94655, μ: 202338, ~: 19168)
        testSwap(9223372036854775808, 1000000, 18232, 16386, Pool.SwapParams(-8384476, true, 65279, 72057594037927935));
    }

    function testSwap(
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
        testModifyLiquidity(
            sqrtPriceX96,
            protocolFee,
            lpFee,
            Pool.ModifyLiquidityParams({
                owner: address(this),
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e18,
                tickSpacing: 60
            })
        );
        Pool.Slot0 memory slot0 = state.slot0;

        while (true) {
            if (params.amountSpecified == 0) {
                vm.expectRevert(Pool.SwapAmountCannotBeZero.selector);
                break;
            }
            if (params.zeroForOne) {
                if (params.sqrtPriceLimitX96 >= slot0.sqrtPriceX96) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                        )
                    );
                    break;
                } else if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                    vm.expectRevert(
                        abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96)
                    );
                    break;
                }
            } else {
                if (params.sqrtPriceLimitX96 <= slot0.sqrtPriceX96) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                        )
                    );
                    break;
                } else if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                    vm.expectRevert(
                        abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96)
                    );
                    break;
                }
            }
            if (params.amountSpecified > 0) {
                if (lpFee == MAX_LP_FEE) {
                    vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
                    break;
                }
            }
            break;
        }

        state.swap(params);

        if (params.zeroForOne) {
            assertGe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        } else {
            assertLe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        }
    }
}
