// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeCast} from "./SafeCast.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {Position} from "./Position.sol";
import {FullMath} from "./FullMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {TickMath} from "./TickMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {SwapMath} from "./SwapMath.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";

library Pool {
    using SafeCast for *;
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Pool for State;

    /// @notice Thrown when tickLower is not below tickUpper
    /// @param tickLower The invalid tickLower
    /// @param tickUpper The invalid tickUpper
    error TicksMisordered(int24 tickLower, int24 tickUpper);

    /// @notice Thrown when tickLower is less than min tick
    /// @param tickLower The invalid tickLower
    error TickLowerOutOfBounds(int24 tickLower);

    /// @notice Thrown when tickUpper exceeds max tick
    /// @param tickUpper The invalid tickUpper
    error TickUpperOutOfBounds(int24 tickUpper);

    /// @notice For the tick spacing, the tick has too much liquidity
    error TickLiquidityOverflow(int24 tick);

    /// @notice Thrown when interacting with an uninitialized tick that must be initialized
    /// @param tick The uninitialized tick
    error TickNotInitialized(int24 tick);

    /// @notice Thrown when trying to initialize an already initialized pool
    error PoolAlreadyInitialized();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when trying to swap amount of 0
    error SwapAmountCannotBeZero();

    /// @notice Thrown when sqrtPriceLimitX96 on a swap has already exceeded its limit
    /// @param sqrtPriceCurrentX96 The invalid, already surpassed sqrtPriceLimitX96
    /// @param sqrtPriceLimitX96 The surpassed price limit
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice Thrown when sqrtPriceLimitX96 lies outside of valid tick/price range
    /// @param sqrtPriceLimitX96 The invalid, out-of-bounds sqrtPriceLimitX96
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    /// @notice Thrown by donate if there is currently 0 liquidity, since the fees will not go to any liquidity providers
    error NoLiquidityToReceiveFees();

    /// @notice Thrown when the amounts and ticks length don't match required for `donate`.
    error LengthMismatch();

    /// @notice Thrown when the ticks list is not submitted in the proper order.
    /// @notice Ticks must be entirely increasing or decreasing. If increasing, they must begin above the current tick. If decreasing, they must start at or below the current tick.
    /// @dev It is not possible to donate to both sides of the current tick in one donate call. It is a "one-sided" donate and the direction depends on the first inputted tick.
    error DonateTicksIncorrectlyOrdered();

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // protocol swap fee represented as integer denominator (1/x), taken as a % of the LP swap fee
        // upper 8 bits are for 1->0, and the lower 8 are for 0->1
        // the minimum permitted denominator is 4 - meaning the maximum protocol fee is 25%
        // granularity is increments of 0.38% (100/type(uint8).max)
        uint16 protocolFee;
        // used for the swap fee, either static at initialize or dynamic via hook
        uint24 swapFee;
    }

    // info stored for each initialized individual tick
    struct TickInfo {
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    /// @dev The state of a pool
    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;
        mapping(int24 => TickInfo) ticks;
        mapping(int16 => uint256) tickBitmap;
        mapping(bytes32 => Position.Info) positions;
    }

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) revert TicksMisordered(tickLower, tickUpper);
        if (tickLower < TickMath.MIN_TICK) revert TickLowerOutOfBounds(tickLower);
        if (tickUpper > TickMath.MAX_TICK) revert TickUpperOutOfBounds(tickUpper);
    }

    function initialize(State storage self, uint160 sqrtPriceX96, uint16 protocolFee, uint24 swapFee)
        internal
        returns (int24 tick)
    {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        self.slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, protocolFee: protocolFee, swapFee: swapFee});
    }

    function setProtocolFee(State storage self, uint16 protocolFee) internal {
        if (self.isNotInitialized()) revert PoolNotInitialized();

        self.slot0.protocolFee = protocolFee;
    }

    /// @notice Only dynamic fee pools may update the swap fee.
    function setSwapFee(State storage self, uint24 swapFee) internal {
        if (self.isNotInitialized()) revert PoolNotInitialized();
        self.slot0.swapFee = swapFee;
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        // the spacing between ticks
        int24 tickSpacing;
    }

    struct ModifyPositionState {
        bool flippedLower;
        uint128 liquidityGrossAfterLower;
        bool flippedUpper;
        uint128 liquidityGrossAfterUpper;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }

    /// @notice Effect changes to a position in a pool
    /// @dev PoolManager checks that the pool is initialized before calling
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return result the deltas of the token balances of the pool
    function modifyPosition(State storage self, ModifyPositionParams memory params)
        internal
        returns (BalanceDelta result)
    {
        checkTicks(params.tickLower, params.tickUpper);

        uint256 feesOwed0;
        uint256 feesOwed1;
        {
            // TODO change this name, overloaded state name
            ModifyPositionState memory state;

            // if we need to update the ticks, do it
            if (params.liquidityDelta != 0) {
                (state.flippedLower, state.liquidityGrossAfterLower) =
                    updateTick(self, params.tickLower, params.liquidityDelta, false);
                (state.flippedUpper, state.liquidityGrossAfterUpper) =
                    updateTick(self, params.tickUpper, params.liquidityDelta, true);

                if (params.liquidityDelta > 0) {
                    uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                    if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                        revert TickLiquidityOverflow(params.tickLower);
                    }
                    if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                        revert TickLiquidityOverflow(params.tickUpper);
                    }
                }

                if (state.flippedLower) {
                    self.tickBitmap.flipTick(params.tickLower, params.tickSpacing);
                }
                if (state.flippedUpper) {
                    self.tickBitmap.flipTick(params.tickUpper, params.tickSpacing);
                }
            }

            // nonzero number
            (state.feeGrowthInside0X128, state.feeGrowthInside1X128) =
                getFeeGrowthInside(self, params.tickLower, params.tickUpper);

            // lastInside is 0
            (feesOwed0, feesOwed1) = self.positions.get(params.owner, params.tickLower, params.tickUpper).update(
                params.liquidityDelta, state.feeGrowthInside0X128, state.feeGrowthInside1X128
            );

            // clear any tick data that is no longer needed
            if (params.liquidityDelta < 0) {
                if (state.flippedLower) {
                    clearTick(self, params.tickLower);
                }
                if (state.flippedUpper) {
                    clearTick(self, params.tickUpper);
                }
            }
        }

        if (params.liquidityDelta != 0) {
            if (self.slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
                result = result
                    + toBalanceDelta(
                        SqrtPriceMath.getAmount0Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower),
                            TickMath.getSqrtRatioAtTick(params.tickUpper),
                            params.liquidityDelta
                        ).toInt128(),
                        0
                    );
            } else if (self.slot0.tick < params.tickUpper) {
                result = result
                    + toBalanceDelta(
                        SqrtPriceMath.getAmount0Delta(
                            self.slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta
                        ).toInt128(),
                        SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower), self.slot0.sqrtPriceX96, params.liquidityDelta
                        ).toInt128()
                    );

                self.liquidity = params.liquidityDelta < 0
                    ? self.liquidity - uint128(-params.liquidityDelta)
                    : self.liquidity + uint128(params.liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
                result = result
                    + toBalanceDelta(
                        0,
                        SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtRatioAtTick(params.tickLower),
                            TickMath.getSqrtRatioAtTick(params.tickUpper),
                            params.liquidityDelta
                        ).toInt128()
                    );
            }
        }

        // Fees earned from LPing are removed from the pool balance.
        result = result - toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
    }

    struct SwapCache {
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the protocol fee for the input token
        uint8 protocolFee;
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    struct SwapParams {
        int24 tickSpacing;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Executes a swap against the state, and returns the amount deltas of the pool
    /// @dev PoolManager checks that the pool is initialized before calling
    function swap(State storage self, SwapParams memory params)
        internal
        returns (BalanceDelta result, uint256 feeForProtocol, uint24 swapFee, SwapState memory state)
    {
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();

        Slot0 memory slot0Start = self.slot0;
        swapFee = slot0Start.swapFee;
        if (params.zeroForOne) {
            if (params.sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96) {
                revert PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96, params.sqrtPriceLimitX96);
            }
            if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
            }
        } else {
            if (params.sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96) {
                revert PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96, params.sqrtPriceLimitX96);
            }
            if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
            }
        }

        SwapCache memory cache = SwapCache({
            liquidityStart: self.liquidity,
            protocolFee: params.zeroForOne ? uint8(slot0Start.protocolFee % 256) : uint8(slot0Start.protocolFee >> 8)
        });

        bool exactInput = params.amountSpecified > 0;

        state = SwapState({
            amountSpecifiedRemaining: params.amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: params.zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
            liquidity: cache.liquidityStart
        });

        StepComputations memory step;
        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != params.sqrtPriceLimitX96) {
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                self.tickBitmap.nextInitializedTickWithinOneWord(state.tick, params.tickSpacing, params.zeroForOne);

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (
                    params.zeroForOne
                        ? step.sqrtPriceNextX96 < params.sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > params.sqrtPriceLimitX96
                ) ? params.sqrtPriceLimitX96 : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                swapFee
            );

            if (exactInput) {
                // safe because we test that amountSpecified > amountIn + feeAmount in SwapMath
                unchecked {
                    state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                }
                state.amountCalculated = state.amountCalculated - step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining += step.amountOut.toInt256();
                }
                state.amountCalculated = state.amountCalculated + (step.amountIn + step.feeAmount).toInt256();
            }

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.protocolFee > 0) {
                // A: calculate the amount of the fee that should go to the protocol
                uint256 delta = step.feeAmount / cache.protocolFee;
                // A: subtract it from the regular fee and add it to the protocol fee
                unchecked {
                    step.feeAmount -= delta;
                    feeForProtocol += delta;
                }
            }

            // update global fee tracker
            if (state.liquidity > 0) {
                unchecked {
                    state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
                }
            }

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    int128 liquidityNet = Pool.crossTick(
                        self,
                        step.tickNext,
                        (params.zeroForOne ? state.feeGrowthGlobalX128 : self.feeGrowthGlobal0X128),
                        (params.zeroForOne ? self.feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    unchecked {
                        if (params.zeroForOne) liquidityNet = -liquidityNet;
                    }

                    state.liquidity = liquidityNet < 0
                        ? state.liquidity - uint128(-liquidityNet)
                        : state.liquidity + uint128(liquidityNet);
                }

                unchecked {
                    state.tick = params.zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (self.slot0.sqrtPriceX96, self.slot0.tick) = (state.sqrtPriceX96, state.tick);

        // update liquidity if it changed
        if (cache.liquidityStart != state.liquidity) self.liquidity = state.liquidity;

        // update fee growth global
        if (params.zeroForOne) {
            self.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            self.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        unchecked {
            if (params.zeroForOne == exactInput) {
                result = toBalanceDelta(
                    (params.amountSpecified - state.amountSpecifiedRemaining).toInt128(),
                    state.amountCalculated.toInt128()
                );
            } else {
                result = toBalanceDelta(
                    state.amountCalculated.toInt128(),
                    (params.amountSpecified - state.amountSpecifiedRemaining).toInt128()
                );
            }
        }
    }

    /// @notice Donates the given amount of currency0 and currency1 to the pool
    /// ticks must be ordered closest to farthest tick, and can only increase or decrease (one-sided) donate
    function donate(
        State storage state,
        uint256[] memory amount0,
        uint256[] memory amount1,
        int24[] memory ticks,
        int24 tickSpacing
    ) internal returns (BalanceDelta delta) {
        if (state.liquidity == 0) revert NoLiquidityToReceiveFees(); // TODO: Can we still allow donating to other ranges if the current liq is 0?
        if (amount0.length != amount1.length || amount1.length != ticks.length) revert LengthMismatch();
        _checkTicks(ticks, ticks[0] <= state.slot0.tick);

        (
            uint256 cumulativeFeeGrowth0X128,
            uint256 cumulativeFeeGrowth1X128,
            uint256[] memory individualFeeGrowth0X128,
            uint256[] memory individualFeeGrowth1X128
        ) = state.calculateDonateFeeGrowth(amount0, amount1, ticks, tickSpacing);

        uint256 total0;
        uint256 total1;
        for (uint256 i = 0; i < ticks.length; i++) {
            int24 tick = ticks[i];
            uint256 feeGrowthOutside0X128Current = state.ticks[tick].feeGrowthOutside0X128;
            state.ticks[tick].feeGrowthOutside0X128 =
                feeGrowthOutside0X128Current + cumulativeFeeGrowth0X128 - individualFeeGrowth0X128[i];

            total0 += amount0[i];
            total1 += amount1[i];
        }

        delta = toBalanceDelta(total0.toInt128(), total1.toInt128());

        /// Note: A more readable algorithm would create a liquidityArray[](ticks.length) saving the liquidity value at every tick
        /// We could then iterate through the liquidityArray twice, calculating first the cumulative amount

        /// And then second, recalculating the individual fee growth and changing the feeGrowthOutisde value for each of the ticks

        /// Similarly, we could save the calculation for the individual fee growth the first time...
    }

    function calculateDonateFeeGrowth(
        State storage state,
        uint256[] memory amount0,
        uint256[] memory amount1,
        int24[] memory ticks,
        int24 tickSpacing
    )
        internal
        returns (
            uint256 cumulativeFeeGrowth0X128,
            uint256 cumulativeFeeGrowth1X128,
            uint256[] memory individualFeeGrowth0X128,
            uint256[] memory individualFeeGrowth1X128
        )
    {
        int24 startTick = ticks[0];
        int24 endTick = ticks[ticks.length - 1];

        int24 tickCurrent = state.slot0.tick;
        bool left = startTick < tickCurrent;
        bool initialized;
        uint128 liquidity = state.liquidity;

        uint256 i = 0; // index

        individualFeeGrowth0X128 = new uint256[](ticks.length);
        individualFeeGrowth1X128 = new uint256[](ticks.length);
        // While we haven't reached the last tick we want to donate to, continue accumulating the cumulativeFeeGrowth value.
        // while (startTick != endTick) <- we must iterate to the endTick otherwise this will not work
        while (left ? tickCurrent > endTick : tickCurrent < endTick) {
            // if the current tick we have iterated down (up) to is lte (gte) the tick we haven't donated to yet but want to, we can accumulate fees. we know the liquidity value is up to date
            while (left ? tickCurrent <= startTick : tickCurrent >= startTick) {
                // edge : what if you have a few ticks you want to donate to that are within the same word..
                // ie the nextInitializedTick blows past 3 ticks you need to update
                // thus I dont think this should check if == but rather it should iterate through the ticks list until the current tick is not caught up

                // when we reach the start tick, use the liquidity value to update the cumulative fee growth
                individualFeeGrowth0X128[i] = FullMath.mulDiv(amount0[i], FixedPoint128.Q128, liquidity);
                cumulativeFeeGrowth0X128 += individualFeeGrowth0X128[i]; // alternatively re-calculate on the way back? tradeoff memory vs. runtime
                individualFeeGrowth0X128[i] = FullMath.mulDiv(amount1[i], FixedPoint128.Q128, liquidity);
                cumulativeFeeGrowth1X128 += individualFeeGrowth1X128[i]; // alternatively re-calculate on the way back? tradeoff memory vs. runtime
                // move to the next tick, increment i
                startTick = ticks[i++]; // does that incrememnt i?
            }

            // @AUSTIN.. can we only bump down on the FIRST left search? or is it all left searches?
            // (left && tickCurrent == state.slot0.tick ? tickCurrent - 1 : tickCurrent)
            (tickCurrent, initialized) = state.tickBitmap.nextInitializedTickWithinOneWord(
                (left ? tickCurrent - 1 : tickCurrent), tickSpacing, left
            );
            if (initialized) {
                int128 liquidityNet = state.ticks[tickCurrent].liquidityNet;
                // @AUSTIN do we need to check direction here too? or does the sign of liquidityNet tell us whether to add/subtract like I assume below:
                liquidity = liquidityNet < 0 ? liquidity + uint128(-liquidityNet) : liquidity + uint128(liquidityNet);
            }
        }
    }

    // @sara TODO: unit tests here...
    // Some thoughts/edge cases:
    // No repeated ticks
    // No ticks on both sides of current
    // No ticks out of bounds.
    // Even with proper increasing the first tick cannot be the max. Even with proper decreasing the first tick cannot be the min.
    function _checkTicks(int24[] memory ticks, bool lte) private {
        for (uint256 i = 0; i < ticks.length - 1; i++) {
            if (lte ? ticks[i] <= ticks[i + 1] : ticks[i] >= ticks[i + 1]) revert DonateTicksIncorrectlyOrdered();
        }

        if (lte) {
            if (ticks[ticks.length - 1] < TickMath.MIN_TICK) revert TickLowerOutOfBounds(ticks[ticks.length - 1]);
        } else if (ticks[ticks.length - 1] > TickMath.MAX_TICK) {
            revert TickUpperOutOfBounds(ticks[ticks.length - 1]);
        }
    }

    /// @notice Retrieves fee growth data
    /// @param self The Pool state struct
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @return feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function getFeeGrowthInside(State storage self, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        TickInfo storage lower = self.ticks[tickLower];
        TickInfo storage upper = self.ticks[tickUpper];
        int24 tickCurrent = self.slot0.tick; // dependent on the current tick, the current tick is the most updated tick

        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128; // 0 - 0 = 0
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
                // in-range, inside SHOULD include the global amount, minus all the fees that were accrued when it was NOT in range
                feeGrowthInside0X128 =
                    self.feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    self.feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            }
        }
    }

    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The tick that will be updated
    /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
    /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
    /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
    /// @return liquidityGrossAfter The total amount of  liquidity for all positions that references the tick after the update
    function updateTick(State storage self, int24 tick, int128 liquidityDelta, bool upper)
        internal
        returns (bool flipped, uint128 liquidityGrossAfter)
    {
        TickInfo storage info = self.ticks[tick];

        uint128 liquidityGrossBefore;
        int128 liquidityNetBefore;
        assembly {
            // load first slot of info which contains liquidityGross and liquidityNet packed
            // where the top 128 bits are liquidityNet and the bottom 128 bits are liquidityGross
            let liquidity := sload(info.slot)
            // slice off top 128 bits of liquidity (liquidityNet) to get just liquidityGross
            liquidityGrossBefore := shr(128, shl(128, liquidity))
            // shift right 128 bits to get just liquidityNet
            liquidityNetBefore := shr(128, liquidity)
        }

        liquidityGrossAfter = liquidityDelta < 0
            ? liquidityGrossBefore - uint128(-liquidityDelta)
            : liquidityGrossBefore + uint128(liquidityDelta);

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // COME BACK TO THIS
            // we are updating an uninitialized tick,(had no positions), now it has a position which is why we r updating
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= self.slot0.tick) {
                info.feeGrowthOutside0X128 = self.feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = self.feeGrowthGlobal1X128;
            }
        }

        // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
        int128 liquidityNet = upper ? liquidityNetBefore - liquidityDelta : liquidityNetBefore + liquidityDelta;
        assembly {
            // liquidityGrossAfter and liquidityNet are packed in the first slot of `info`
            // So we can store them with a single sstore by packing them ourselves first
            sstore(
                info.slot,
                // bitwise OR to pack liquidityGrossAfter and liquidityNet
                or(
                    // liquidityGross is in the low bits, upper bits are already 0
                    liquidityGrossAfter,
                    // shift liquidityNet to take the upper bits and lower bits get filled with 0
                    shl(128, liquidityNet)
                )
            )
        }
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed within the pool constructor
    /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return The max liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        unchecked {
            return uint128(
                (type(uint128).max * uint256(int256(tickSpacing)))
                    / uint256(int256(TickMath.MAX_TICK * 2 + tickSpacing))
            );
        }
    }

    function isNotInitialized(State storage self) internal view returns (bool) {
        return self.slot0.sqrtPriceX96 == 0;
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clearTick(State storage self, int24 tick) internal {
        delete self.ticks[tick];
    }

    /// @notice Transitions to next tick as needed by price movement
    /// @param self The Pool state struct
    /// @param tick The destination tick of the transition
    /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
    /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
    function crossTick(State storage self, int24 tick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
        internal
        returns (int128 liquidityNet)
    {
        unchecked {
            TickInfo storage info = self.ticks[tick];
            info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
            info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
            liquidityNet = info.liquidityNet;
        }
    }
}
