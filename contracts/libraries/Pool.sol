// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {SafeCast} from './SafeCast.sol';
import {Tick} from './Tick.sol';
import {TickBitmap} from './TickBitmap.sol';
import {Position} from './Position.sol';
import {FullMath} from './FullMath.sol';
import {FixedPoint128} from './FixedPoint128.sol';
import {TickMath} from './TickMath.sol';
import {SqrtPriceMath} from './SqrtPriceMath.sol';
import {SwapMath} from './SwapMath.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

library Pool {
    using SafeCast for *;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

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

    /// @notice Thrown by donate if there is currently 0 liquidity, since the fees will not go to any liquidity providers
    error NoLiquidityToReceiveFees();

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        // First 4 bits are the fee for trading 1 for 0, and the latter 4 for 0 for 1
        uint8 protocolFee;
        // 64 bits left!
    }

    /// @dev The state of a pool
    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;
        mapping(int24 => Tick.Info) ticks;
        mapping(int16 => uint256) tickBitmap;
        mapping(bytes32 => Position.Info) positions;
    }

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) revert TicksMisordered(tickLower, tickUpper);
        if (tickLower < TickMath.MIN_TICK) revert TickLowerOutOfBounds(tickLower);
        if (tickUpper > TickMath.MAX_TICK) revert TickUpperOutOfBounds(tickUpper);
    }

    function initialize(
        State storage self,
        uint160 sqrtPriceX96,
        uint8 protocolFee
    ) internal returns (int24 tick) {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        self.slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, protocolFee: protocolFee});
    }

    function setProtocolFee(State storage self, uint8 newProtocolFee) internal {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();

        self.slot0.protocolFee = newProtocolFee;
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
                (state.flippedLower, state.liquidityGrossAfterLower) = self.ticks.update(
                    params.tickLower,
                    self.slot0.tick,
                    params.liquidityDelta,
                    self.feeGrowthGlobal0X128,
                    self.feeGrowthGlobal1X128,
                    false
                );
                (state.flippedUpper, state.liquidityGrossAfterUpper) = self.ticks.update(
                    params.tickUpper,
                    self.slot0.tick,
                    params.liquidityDelta,
                    self.feeGrowthGlobal0X128,
                    self.feeGrowthGlobal1X128,
                    true
                );

                if (params.liquidityDelta > 0) {
                    uint128 maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                    if (state.liquidityGrossAfterLower > maxLiquidityPerTick)
                        revert TickLiquidityOverflow(params.tickLower);
                    if (state.liquidityGrossAfterUpper > maxLiquidityPerTick)
                        revert TickLiquidityOverflow(params.tickUpper);
                }

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
        uint24 fee;
        int24 tickSpacing;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @dev Executes a swap against the state, and returns the amount deltas of the pool
    function swap(State storage self, SwapParams memory params)
        internal
        returns (IPoolManager.BalanceDelta memory result, uint256 feeForProtocol)
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
            protocolFee: params.zeroForOne ? (slot0Start.protocolFee % 16) : (slot0Start.protocolFee >> 4)
        });

        bool exactInput = params.amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: params.amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: params.zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
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
                    int128 liquidityNet = self.ticks.cross(
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
            (result.amount0, result.amount1) = params.zeroForOne == exactInput
                ? (params.amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
                : (state.amountCalculated, params.amountSpecified - state.amountSpecifiedRemaining);
        }
    }

    /// @notice Donates the given amount of token0 and token1 to the pool
    function donate(
        State storage state,
        uint256 amount0,
        uint256 amount1
    ) internal returns (IPoolManager.BalanceDelta memory delta) {
        if (state.liquidity == 0) revert NoLiquidityToReceiveFees();
        delta.amount0 = amount0.toInt256();
        delta.amount1 = amount1.toInt256();
        unchecked {
            if (amount0 > 0)
                state.feeGrowthGlobal0X128 += FullMath.mulDiv(amount0, FixedPoint128.Q128, state.liquidity);
            if (amount1 > 0)
                state.feeGrowthGlobal1X128 += FullMath.mulDiv(amount1, FixedPoint128.Q128, state.liquidity);
        }
    }
}
