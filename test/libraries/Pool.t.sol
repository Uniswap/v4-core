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
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract PoolTest is Test, GasSnapshot {
    using Pool for Pool.State;
    using LPFeeLibrary for uint24;
    using ProtocolFeeLibrary for uint24;

    Pool.State state;

    uint24 constant MAX_PROTOCOL_FEE = ProtocolFeeLibrary.MAX_PROTOCOL_FEE; // 0.1%
    uint24 constant MAX_LP_FEE = LPFeeLibrary.MAX_LP_FEE; // 100%

    function test_fuzz_initialize(uint160 sqrtPriceX96, uint24 protocolFee, uint24 swapFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            vm.expectRevert(TickMath.InvalidSqrtPrice.selector);
            state.initialize(sqrtPriceX96, protocolFee, swapFee);
        } else {
            state.initialize(sqrtPriceX96, protocolFee, swapFee);
            assertEq(state.slot0.sqrtPriceX96(), sqrtPriceX96);
            assertEq(state.slot0.protocolFee(), protocolFee);
            assertEq(state.slot0.tick(), TickMath.getTickAtSqrtPrice(sqrtPriceX96));
            assertLt(state.slot0.tick(), TickMath.MAX_TICK);
            assertGt(state.slot0.tick(), TickMath.MIN_TICK - 1);
        }
    }

    function test_initialize_updatesState() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
        assertEq(state.slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(state.slot0.protocolFee(), protocolFee);
        assertEq(state.slot0.tick(), TickMath.getTickAtSqrtPrice(sqrtPriceX96));
        assertLt(state.slot0.tick(), TickMath.MAX_TICK);
        assertGt(state.slot0.tick(), TickMath.MIN_TICK - 1);
    }

    function test_initialize_revertsWithInvalidSqrtPrice_tooLow() public {
        uint160 sqrtPriceX96 = TickMath.MIN_SQRT_PRICE - 1;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        vm.expectRevert(TickMath.InvalidSqrtPrice.selector);
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
    }

    function test_initialize_revertsWithInvalidSqrtPrice_tooHigh() public {
        uint160 sqrtPriceX96 = TickMath.MAX_SQRT_PRICE;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        vm.expectRevert(TickMath.InvalidSqrtPrice.selector);
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
    }

    function test_initialize_revertsWithPoolAlreadyInitialized() public {
        uint160 sqrtPriceX96 = TickMath.MIN_SQRT_PRICE;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
    }

    function test_fuzz_setProtocolFee(
        uint160 sqrtPriceX96,
        uint24 protocolFee,
        uint24 lpFee,
        uint24 newProtocolFee,
        bool initialized
    ) public {
        if (initialized) {
            test_fuzz_initialize(sqrtPriceX96, protocolFee, lpFee);
            state.setProtocolFee(newProtocolFee);
            assertEq(state.slot0.protocolFee(), newProtocolFee);
        } else {
            vm.expectRevert(Pool.PoolNotInitialized.selector);
            state.setProtocolFee(newProtocolFee);
        }
    }

    function test_setProtocolFee_setsCorrectFee() public {
        uint160 sqrtPriceX96 = TickMath.MIN_SQRT_PRICE;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        uint24 newProtocolFee = 5000;
        test_fuzz_initialize(sqrtPriceX96, protocolFee, lpFee);
        state.setProtocolFee(newProtocolFee);
        assertEq(state.slot0.protocolFee(), newProtocolFee);
    }

    function test_setProtocolFee_revertsWithPoolNotInitialized() public {
        uint24 newProtocolFee = 5000;
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        state.setProtocolFee(newProtocolFee);
    }

    function test_fuzz_setLpFee(
        uint160 sqrtPriceX96,
        uint24 protocolFee,
        uint24 lpFee,
        uint24 newLpFee,
        bool initialized
    ) public {
        if (initialized) {
            test_fuzz_initialize(sqrtPriceX96, protocolFee, lpFee);
            state.setLPFee(newLpFee);
            assertEq(state.slot0.lpFee(), newLpFee);
        } else {
            vm.expectRevert(Pool.PoolNotInitialized.selector);
            state.setLPFee(newLpFee);
        }
    }

    function test_setLPFee_succeedsWithNewFee() public {
        uint160 sqrtPriceX96 = TickMath.MIN_SQRT_PRICE;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        uint24 newLpFee = 5000;
        test_fuzz_initialize(sqrtPriceX96, protocolFee, lpFee);
        state.setLPFee(newLpFee);
        assertEq(state.slot0.lpFee(), newLpFee);
    }

    function test_setLPFee_revertsWithPoolNotInitialized() public {
        uint24 newLpFee = 5000;
        vm.expectRevert(Pool.PoolNotInitialized.selector);
        state.setLPFee(newLpFee);
    }

    function test_fuzz_modifyLiquidity(
        uint160 sqrtPriceX96,
        uint24 protocolFee,
        uint24 lpFee,
        Pool.ModifyLiquidityParams memory params
    ) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        test_fuzz_initialize(sqrtPriceX96, protocolFee, lpFee);

        // currently an empty position
        if (params.tickLower >= params.tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, params.tickLower, params.tickUpper));
        } else if (params.tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, params.tickLower));
        } else if (params.tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, params.tickUpper));
        } else if (params.liquidityDelta < 0) {
            // can't remove liquidity before adding it
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        } else if (params.liquidityDelta == 0) {
            // b/c position is empty
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        } else if (params.liquidityDelta > int128(Pool.tickSpacingToMaxLiquidityPerTick(params.tickSpacing))) {
            // b/c liquidity before starts at 0
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, params.tickLower));
        } else if (params.tickLower % params.tickSpacing != 0) {
            // since tick will always be flipped first time
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickLower, params.tickSpacing)
            );
        } else if (params.tickUpper % params.tickSpacing != 0) {
            // since tick will always be flipped first time
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickUpper, params.tickSpacing)
            );
        } else {
            // We need the assumptions above to calculate this
            uint256 maxInt128InTypeUint256 = uint256(uint128(type(int128).max));
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(params.tickLower),
                TickMath.getSqrtPriceAtTick(params.tickUpper),
                uint128(params.liquidityDelta)
            );

            // fuzz test not checking this
            if ((amount0 > maxInt128InTypeUint256) || (amount1 > maxInt128InTypeUint256)) {
                vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
            }
        }

        params.owner = address(this);
        state.modifyLiquidity(params);
    }

    function test_modifyLiquidity_revertsWithTickLiquidityOverflow_lower() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
        Pool.ModifyLiquidityParams memory params = Pool.ModifyLiquidityParams({
            owner: address(this),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1e18,
            tickSpacing: 60,
            salt: 0
        });
        state.ticks[-120] = Pool.TickInfo({
            liquidityGross: type(uint128).max - uint128(params.liquidityDelta),
            liquidityNet: 0,
            feeGrowthOutside0X128: 0,
            feeGrowthOutside1X128: 0
        });
        vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, -120));
        state.modifyLiquidity(params);
    }

    function test_modifyLiquidity_revertsWithTickLiquidityOverflow_upper() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = MAX_PROTOCOL_FEE;
        uint24 lpFee = 3000;
        state.initialize(sqrtPriceX96, protocolFee, lpFee);
        Pool.ModifyLiquidityParams memory params = Pool.ModifyLiquidityParams({
            owner: address(this),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1e18,
            tickSpacing: 60,
            salt: 0
        });
        state.ticks[120] = Pool.TickInfo({
            liquidityGross: type(uint128).max - uint128(params.liquidityDelta),
            liquidityNet: 0,
            feeGrowthOutside0X128: 0,
            feeGrowthOutside1X128: 0
        });
        vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, 120));
        state.modifyLiquidity(params);
    }

    function test_fuzz_swap(
        uint160 sqrtPriceX96,
        uint24 lpFee,
        uint16 protocolFee0,
        uint16 protocolFee1,
        Pool.SwapParams memory params,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) public {
        // Assumptions tested in PoolManager.t.sol
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        lpFee = uint24(bound(lpFee, 0, MAX_LP_FEE));
        protocolFee0 = uint16(bound(protocolFee0, 0, MAX_PROTOCOL_FEE));
        protocolFee1 = uint16(bound(protocolFee1, 0, MAX_PROTOCOL_FEE));
        uint24 protocolFee = protocolFee1 << 12 | protocolFee0;
        liquidityDelta = int128(bound(liquidityDelta, 1, type(int128).max));

        vm.assume(tickLower < tickUpper);

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
            lpFee,
            Pool.ModifyLiquidityParams({
                owner: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                tickSpacing: params.tickSpacing,
                salt: 0
            })
        );
        Slot0 slot0 = state.slot0;

        uint24 _lpFee = params.lpFeeOverride.isOverride() ? params.lpFeeOverride.removeOverrideFlag() : lpFee;
        uint24 swapFee = protocolFee == 0 ? _lpFee : uint24(protocolFee).calculateSwapFee(_lpFee);

        if (params.amountSpecified >= 0 && swapFee == MAX_LP_FEE) {
            vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
        } else if (!swapFee.isValid()) {
            vm.expectRevert(LPFeeLibrary.FeeTooLarge.selector);
        } else if (params.zeroForOne && params.amountSpecified != 0) {
            if (params.sqrtPriceLimitX96 >= slot0.sqrtPriceX96()) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_PRICE) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        } else if (!params.zeroForOne && params.amountSpecified != 0) {
            if (params.sqrtPriceLimitX96 <= slot0.sqrtPriceX96()) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_PRICE) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        }

        uint160 sqrtPriceBefore = state.slot0.sqrtPriceX96();
        state.swap(params);

        if (params.amountSpecified == 0) {
            assertEq(sqrtPriceBefore, state.slot0.sqrtPriceX96(), "amountSpecified == 0");
        } else if (params.zeroForOne) {
            // fuzz test not checking this, checking in unit test: test_swap_zeroForOne_priceGreaterThanOrEqualToLimit
            assertGe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "zeroForOne");
        } else {
            // fuzz test not checking this, checking in unit test: test_swap_oneForZero_priceLessThanOrEqualToLimit
            assertLe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "oneForZero");
        }
    }

    function test_swap_withProtocolFee() public {
        // not sure why line 380 is not being covered when this test has a protocol fee of over 1000
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 1000;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: TickMath.MIN_TICK_SPACING,
            zeroForOne: true,
            amountSpecified: 2459,
            sqrtPriceLimitX96: Constants.SQRT_PRICE_1_2,
            lpFeeOverride: 0
        });

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        state.swap(params);
    }

    function test_swap_revertsWithPriceLimitAlreadyExceeded_zeroForOne() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: TickMath.MIN_TICK_SPACING,
            zeroForOne: true,
            amountSpecified: 2459,
            sqrtPriceLimitX96: Constants.SQRT_PRICE_1_1,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        vm.expectRevert(
            abi.encodeWithSelector(
                Pool.PriceLimitAlreadyExceeded.selector, state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
            )
        );
        state.swap(params);
    }

    function test_swap_revertsWithPriceLimitOutOfBounds_zeroForOne() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: TickMath.MIN_TICK_SPACING,
            zeroForOne: true,
            amountSpecified: 2459,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
        state.swap(params);
    }

    function test_swap_revertsWithPriceLimitAlreadyExceeded_oneForZero() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: TickMath.MIN_TICK_SPACING,
            zeroForOne: false,
            amountSpecified: 2459,
            sqrtPriceLimitX96: Constants.SQRT_PRICE_1_1 - 1,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        vm.expectRevert(
            abi.encodeWithSelector(
                Pool.PriceLimitAlreadyExceeded.selector, state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96
            )
        );
        state.swap(params);
    }

    function test_swap_revertsWithPriceLimitOutOfBounds_oneForZero() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: TickMath.MIN_TICK_SPACING,
            zeroForOne: false,
            amountSpecified: 2459,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
        state.swap(params);
    }

    function test_swap_oneForZero_priceLessThanOrEqualToLimit() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: -2448282,
            zeroForOne: false,
            amountSpecified: 2459,
            sqrtPriceLimitX96: Constants.SQRT_PRICE_2_1,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        state.swap(params);

        assertLe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "oneForZero");
    }

    function test_swap_zeroForOne_priceGreaterThanOrEqualToLimit() public {
        uint160 sqrtPriceX96 = Constants.SQRT_PRICE_1_1;
        uint24 protocolFee = 0;
        uint24 lpFee = 0;
        Pool.SwapParams memory params = Pool.SwapParams({
            tickSpacing: -2448282,
            zeroForOne: true,
            amountSpecified: 2459,
            sqrtPriceLimitX96: Constants.SQRT_PRICE_1_2,
            lpFeeOverride: 0
        });
        params.tickSpacing = int24(bound(params.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        // initialize and add liquidity
        test_fuzz_modifyLiquidity(
            sqrtPriceX96,
            protocolFee,
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

        state.swap(params);

        assertGe(state.slot0.sqrtPriceX96(), params.sqrtPriceLimitX96, "zeroForOne");
    }

    function test_fuzz_donate(
        uint160 sqrtPriceX96,
        Pool.ModifyLiquidityParams memory params,
        uint24 lpFee,
        uint24 protocolFee,
        uint256 amount0,
        uint256 amount1
    ) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        params.tickUpper = int24(bound(params.tickUpper, TickMath.getTickAtSqrtPrice(sqrtPriceX96), TickMath.MAX_TICK));
        params.tickLower = int24(bound(params.tickLower, TickMath.MIN_TICK, TickMath.getTickAtSqrtPrice(sqrtPriceX96)));
        amount0 = bound(amount0, 0, uint256(int256(type(int128).max)));
        amount1 = bound(amount1, 0, uint256(int256(type(int128).max)));

        vm.expectRevert(Pool.NoLiquidityToReceiveFees.selector);
        state.donate(amount0, amount1);

        test_fuzz_modifyLiquidity(sqrtPriceX96, protocolFee, lpFee, params);
        state.donate(amount0, amount1);
    }

    function test_fuzz_tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) public pure {
        tickSpacing = int24(bound(tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        // v3 math
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        // assert that the result is the same as the v3 math
        assertEq(type(uint128).max / numTicks, Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing));
    }
}
