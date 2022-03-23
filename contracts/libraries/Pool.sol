// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {SafeCast} from './SafeCast.sol';
import {Tick} from './Tick.sol';
import {TickBitmap} from './TickBitmap.sol';
import {Position} from './Position.sol';
import {Oracle} from './Oracle.sol';
import {FullMath} from './FullMath.sol';
import {FixedPoint128} from './FixedPoint128.sol';
import {TickMath} from './TickMath.sol';
import {SqrtPriceMath} from './SqrtPriceMath.sol';
import {SwapMath} from './SwapMath.sol';
import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

library Pool {
    using SafeCast for *;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];

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

    /// @notice Thrown when interacting with an uninitialized tick that must be initialized
    /// @param tick The uninitialized tick
    error TickNotInitialized(int24 tick);

    /// @notice Thrown when trying to initalize an already initialized pool
    error PoolAlreadyInitialized();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when trying to swap amount of 0
    error SwapAmountCannotBeZero();

    /// @notice Thrown when sqrtPriceLimitX96 on a swap has already exceeded its limit
    /// @param sqrtPriceCurrentX96 The invalid, already surpassed sqrtPriceLimitX96
    /// @param sqrtPriceLimitX96 The invalid, already surpassed sqrtPriceLimitX96
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice Thrown when sqrtPriceLimitX96 lies outside of valid tick/price range
    /// @param sqrtPriceLimitX96 The invalid, out-of-bounds sqrtPriceLimitX96
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    /// @notice Thrown when trying to set an invalid protocol fee
    /// @param feeProtocol The invalid feeProtocol
    error InvalidFeeProtocol(uint8 feeProtocol);

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
    }

    // accumulated protocol fees in token0/token1 units
    // todo: this might be better accumulated in a pool
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }

    /// @dev The state of a pool
    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        ProtocolFees protocolFees;
        uint128 liquidity;
        mapping(int24 => Tick.Info) ticks;
        mapping(int16 => uint256) tickBitmap;
        mapping(bytes32 => Position.Info) positions;
        Oracle.Observation[65535] observations;
    }

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) revert TicksMisordered(tickLower, tickUpper);
        if (tickLower < TickMath.MIN_TICK) revert TickLowerOutOfBounds(tickLower);
        if (tickUpper > TickMath.MAX_TICK) revert TickUpperOutOfBounds(tickUpper);
    }

    struct SnapshotCumulativesInsideState {
        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;
    }

    struct Snapshot {
        int56 tickCumulativeInside;
        uint160 secondsPerLiquidityInsideX128;
        uint32 secondsInside;
    }

    /// @dev Take a snapshot of the cumulative values inside a tick range, only consistent as long as a position has non-zero liquidity
    function snapshotCumulativesInside(
        State storage self,
        int24 tickLower,
        int24 tickUpper,
        uint32 time
    ) internal view returns (Snapshot memory result) {
        checkTicks(tickLower, tickUpper);

        SnapshotCumulativesInsideState memory state;
        {
            Tick.Info storage lower = self.ticks[tickLower];
            Tick.Info storage upper = self.ticks[tickUpper];
            bool initializedLower;
            (
                state.tickCumulativeLower,
                state.secondsPerLiquidityOutsideLowerX128,
                state.secondsOutsideLower,
                initializedLower
            ) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            if (!initializedLower) revert TickNotInitialized(tickLower);

            bool initializedUpper;
            (
                state.tickCumulativeUpper,
                state.secondsPerLiquidityOutsideUpperX128,
                state.secondsOutsideUpper,
                initializedUpper
            ) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            if (!initializedUpper) revert TickNotInitialized(tickUpper);
        }

        Slot0 memory _slot0 = self.slot0;

        unchecked {
            if (_slot0.tick < tickLower) {
                result.tickCumulativeInside = state.tickCumulativeLower - state.tickCumulativeUpper;
                result.secondsPerLiquidityInsideX128 =
                    state.secondsPerLiquidityOutsideLowerX128 -
                    state.secondsPerLiquidityOutsideUpperX128;
                result.secondsInside = state.secondsOutsideLower - state.secondsOutsideUpper;
            } else if (_slot0.tick < tickUpper) {
                (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = self.observations.observeSingle(
                    time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    self.liquidity,
                    _slot0.observationCardinality
                );
                result.tickCumulativeInside = tickCumulative - state.tickCumulativeLower - state.tickCumulativeUpper;
                result.secondsPerLiquidityInsideX128 =
                    secondsPerLiquidityCumulativeX128 -
                    state.secondsPerLiquidityOutsideLowerX128 -
                    state.secondsPerLiquidityOutsideUpperX128;
                result.secondsInside = time - state.secondsOutsideLower - state.secondsOutsideUpper;
            } else {
                result.tickCumulativeInside = state.tickCumulativeUpper - state.tickCumulativeLower;
                result.secondsPerLiquidityInsideX128 =
                    state.secondsPerLiquidityOutsideUpperX128 -
                    state.secondsPerLiquidityOutsideLowerX128;
                result.secondsInside = state.secondsOutsideUpper - state.secondsOutsideLower;
            }
        }
    }

    function observe(
        State storage self,
        uint32 time,
        uint32[] calldata secondsAgos
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        return
            self.observations.observe(
                time,
                secondsAgos,
                self.slot0.tick,
                self.slot0.observationIndex,
                self.liquidity,
                self.slot0.observationCardinality
            );
    }

    function initialize(
        State storage self,
        uint32 time,
        uint160 sqrtPriceX96
    ) internal returns (int24 tick) {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = self.observations.initialize(time);

        self.slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0
        });
    }

    /// @dev Increase the number of stored observations
    function increaseObservationCardinalityNext(State storage self, uint16 observationCardinalityNext)
        internal
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
    {
        observationCardinalityNextOld = self.slot0.observationCardinalityNext;
        observationCardinalityNextNew = self.observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        self.slot0.observationCardinalityNext = observationCardinalityNextNew;
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        // current time
        uint32 time;
        // the max liquidity per tick
        uint128 maxLiquidityPerTick;
        // the spacing between ticks
        int24 tickSpacing;
    }

    struct ModifyPositionState {
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool flippedLower;
        bool flippedUpper;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }

    /// @dev Effect changes to a position in a pool
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return result the deltas of the token balances of the pool
    function modifyPosition(State storage self, ModifyPositionParams memory params)
        internal
        returns (IPoolManager.BalanceDelta memory result)
    {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();

        checkTicks(params.tickLower, params.tickUpper);

        {
            ModifyPositionState memory state;
            // if we need to update the ticks, do it
            if (params.liquidityDelta != 0) {
                (state.tickCumulative, state.secondsPerLiquidityCumulativeX128) = self.observations.observeSingle(
                    params.time,
                    0,
                    self.slot0.tick,
                    self.slot0.observationIndex,
                    self.liquidity,
                    self.slot0.observationCardinality
                );

                state.flippedLower = self.ticks.update(
                    params.tickLower,
                    self.slot0.tick,
                    params.liquidityDelta,
                    self.feeGrowthGlobal0X128,
                    self.feeGrowthGlobal1X128,
                    state.secondsPerLiquidityCumulativeX128,
                    state.tickCumulative,
                    params.time,
                    false,
                    params.maxLiquidityPerTick
                );
                state.flippedUpper = self.ticks.update(
                    params.tickUpper,
                    self.slot0.tick,
                    params.liquidityDelta,
                    self.feeGrowthGlobal0X128,
                    self.feeGrowthGlobal1X128,
                    state.secondsPerLiquidityCumulativeX128,
                    state.tickCumulative,
                    params.time,
                    true,
                    params.maxLiquidityPerTick
                );

                if (state.flippedLower) {
                    self.tickBitmap.flipTick(params.tickLower, params.tickSpacing);
                }
                if (state.flippedUpper) {
                    self.tickBitmap.flipTick(params.tickUpper, params.tickSpacing);
                }
            }

            (state.feeGrowthInside0X128, state.feeGrowthInside1X128) = self.ticks.getFeeGrowthInside(
                params.tickLower,
                params.tickUpper,
                self.slot0.tick,
                self.feeGrowthGlobal0X128,
                self.feeGrowthGlobal1X128
            );

            (uint256 feesOwed0, uint256 feesOwed1) = self
                .positions
                .get(params.owner, params.tickLower, params.tickUpper)
                .update(params.liquidityDelta, state.feeGrowthInside0X128, state.feeGrowthInside1X128);
            result.amount0 -= feesOwed0.toInt256();
            result.amount1 -= feesOwed1.toInt256();

            // clear any tick data that is no longer needed
            if (params.liquidityDelta < 0) {
                if (state.flippedLower) {
                    self.ticks.clear(params.tickLower);
                }
                if (state.flippedUpper) {
                    self.ticks.clear(params.tickUpper);
                }
            }
        }

        if (params.liquidityDelta != 0) {
            if (self.slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                result.amount0 += SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (self.slot0.tick < params.tickUpper) {
                // current tick is inside the passed range, must modify liquidity
                // write an oracle entry
                (self.slot0.observationIndex, self.slot0.observationCardinality) = self.observations.write(
                    self.slot0.observationIndex,
                    params.time,
                    self.slot0.tick,
                    self.liquidity,
                    self.slot0.observationCardinality,
                    self.slot0.observationCardinalityNext
                );

                result.amount0 += SqrtPriceMath.getAmount0Delta(
                    self.slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                result.amount1 += SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    self.slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                self.liquidity = params.liquidityDelta < 0
                    ? self.liquidity - uint128(-params.liquidityDelta)
                    : self.liquidity + uint128(params.liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                result.amount1 += SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    struct SwapCache {
        // the protocol fee for the input token
        uint8 feeProtocol;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
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
        // amount of input token paid as protocol fee
        uint128 protocolFee;
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
        uint24 fee;
        int24 tickSpacing;
        uint32 time;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @dev Executes a swap against the state, and returns the amount deltas of the pool
    function swap(State storage self, SwapParams memory params)
        internal
        returns (IPoolManager.BalanceDelta memory result)
    {
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();

        Slot0 memory slot0Start = self.slot0;
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();
        if (params.zeroForOne) {
            if (params.sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96)
                revert PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96, params.sqrtPriceLimitX96);
            if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO)
                revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
        } else {
            if (params.sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96)
                revert PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96, params.sqrtPriceLimitX96);
            if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO)
                revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
        }

        SwapCache memory cache = SwapCache({
            liquidityStart: self.liquidity,
            feeProtocol: params.zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
            secondsPerLiquidityCumulativeX128: 0,
            tickCumulative: 0,
            computedLatestObservation: false
        });

        bool exactInput = params.amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: params.amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: params.zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != params.sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = self.tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                params.tickSpacing,
                params.zeroForOne
            );

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
                )
                    ? params.sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                params.fee
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
            if (cache.feeProtocol > 0) {
                unchecked {
                    uint256 delta = step.feeAmount / cache.feeProtocol;
                    step.feeAmount -= delta;
                    state.protocolFee += uint128(delta);
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
                    // check for the placeholder value, which we replace with the actual value the first time the swap
                    // crosses an initialized tick
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = self
                            .observations
                            .observeSingle(
                                params.time,
                                0,
                                slot0Start.tick,
                                slot0Start.observationIndex,
                                cache.liquidityStart,
                                slot0Start.observationCardinality
                            );
                        cache.computedLatestObservation = true;
                    }

                    int128 liquidityNet = self.ticks.cross(
                        step.tickNext,
                        (params.zeroForOne ? state.feeGrowthGlobalX128 : self.feeGrowthGlobal0X128),
                        (params.zeroForOne ? self.feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        params.time
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

        // update tick and write an oracle entry if the tick change
        if (state.tick != slot0Start.tick) {
            (self.slot0.observationIndex, self.slot0.observationCardinality) = self.observations.write(
                slot0Start.observationIndex,
                params.time,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (self.slot0.sqrtPriceX96, self.slot0.tick) = (state.sqrtPriceX96, state.tick);
        } else {
            // otherwise just update the price
            self.slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        if (cache.liquidityStart != state.liquidity) self.liquidity = state.liquidity;

        // update fee growth global and, if necessary, protocol fees
        // overflow is acceptable, protocol has to withdraw before it hits type(uint128).max fees
        if (params.zeroForOne) {
            self.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) self.protocolFees.token0 += state.protocolFee;
            }
        } else {
            self.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) self.protocolFees.token1 += state.protocolFee;
            }
        }

        unchecked {
            (result.amount0, result.amount1) = params.zeroForOne == exactInput
                ? (params.amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
                : (state.amountCalculated, params.amountSpecified - state.amountSpecifiedRemaining);
        }
    }

    /// @notice Updates the protocol fee for a given pool
    function setFeeProtocol(State storage self, uint8 feeProtocol) internal returns (uint8 feeProtocolOld) {
        (uint8 feeProtocol0, uint8 feeProtocol1) = (feeProtocol >> 4, feeProtocol % 16);
        if (
            (feeProtocol0 != 0 && (feeProtocol0 < 4 || feeProtocol0 > 10)) ||
            (feeProtocol1 != 0 && (feeProtocol1 < 4 || feeProtocol1 > 10))
        ) revert InvalidFeeProtocol(feeProtocol);
        feeProtocolOld = self.slot0.feeProtocol;
        self.slot0.feeProtocol = feeProtocol;
    }
}
