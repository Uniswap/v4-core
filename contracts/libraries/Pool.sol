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
    /// @param sqrtPriceLimitX96 The surpassed price limit
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice Thrown when sqrtPriceLimitX96 lies outside of valid tick/price range
    /// @param sqrtPriceLimitX96 The invalid, out-of-bounds sqrtPriceLimitX96
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    /// @notice Thrown by donate if there is currently 0 liquidity, since the fees will not go to any liquidity providers
    error NoLiquidityToReceiveFees();

    /// Each uint24 variable packs both the swap fees and the withdraw fees represented as integer denominators (1/x). The upper 12 bits are the swap fees, and the lower 12 bits
    /// are the withdraw fees. For swap fees, the upper 6 bits are the fee for trading 1 for 0, and the lower 6 are for 0 for 1 and are taken as a percentage of the lp swap fee.
    /// For withdraw fees the upper 6 bits are the fee on amount1, and the lower 6 are for amount0 and are taken as a percentage of the principle amount of the underlying position.
    /// bits          24 22 20 18 16 14 12 10 8  6  4  2  0
    ///               |    swapFees     |   withdrawFees  |
    ///               ┌────────┬────────┬────────┬────────┐
    /// protocolFees: | 1->0   |  0->1  |  fee1  |  fee0  |
    /// hookFees:     | 1->0   |  0->1  |  fee1  |  fee0  |
    ///               └────────┴────────┴────────┴────────┘
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        uint24 protocolFees;
        uint24 hookFees;
        // used for the dynamicFee if there is one enabled
        uint24 dynamicFee;
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

    function initialize(
        State storage self,
        uint160 sqrtPriceX96,
        uint24 protocolFees,
        uint24 hookFees,
        uint24 dynamicFee
    ) internal returns (int24 tick) {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        self.slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            protocolFees: protocolFees,
            hookFees: hookFees,
            dynamicFee: dynamicFee
        });
    }

    function getSwapFee(uint24 feesStorage) internal pure returns (uint16) {
        return uint16(feesStorage >> 12);
    }

    function getWithdrawFee(uint24 feesStorage) internal pure returns (uint16) {
        return uint16(feesStorage & 0xFFF);
    }

    function setProtocolFees(State storage self, uint24 protocolFees) internal {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();

        self.slot0.protocolFees = protocolFees;
    }

    function setHookFees(State storage self, uint24 hookFees) internal {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();

        self.slot0.hookFees = hookFees;
    }

    function setDynamicFee(State storage self, uint24 dynamicFee) internal {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();
        self.slot0.dynamicFee = dynamicFee;
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

    struct FeeAmounts {
        uint256 feeForProtocol0;
        uint256 feeForProtocol1;
        uint256 feeForHook0;
        uint256 feeForHook1;
    }

    /// @dev Effect changes to a position in a pool
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return result the deltas of the token balances of the pool
    function modifyPosition(State storage self, ModifyPositionParams memory params)
        internal
        returns (BalanceDelta result, FeeAmounts memory fees)
    {
        if (self.slot0.sqrtPriceX96 == 0) revert PoolNotInitialized();

        checkTicks(params.tickLower, params.tickUpper);

        uint256 feesOwed0;
        uint256 feesOwed1;
        {
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

            (state.feeGrowthInside0X128, state.feeGrowthInside1X128) =
                getFeeGrowthInside(self, params.tickLower, params.tickUpper);

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

        if (params.liquidityDelta < 0 && getWithdrawFee(self.slot0.hookFees) > 0) {
            // Only take fees if the hook withdraw fee is set and the liquidity is being removed.
            fees = _calculateExternalFees(self, result);

            // Amounts are balances owed to the pool. When negative, they represent the balance a user can take.
            // Since protocol and hook fees are extracted on the balance a user can take
            // they are owed (added) back to the pool where they are kept to be collected by the fee recipients.
            result = result
                + toBalanceDelta(
                    fees.feeForHook0.toInt128() + fees.feeForProtocol0.toInt128(),
                    fees.feeForHook1.toInt128() + fees.feeForProtocol1.toInt128()
                );
        }

        // Fees earned from LPing are removed from the pool balance.
        result = result - toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
    }

    function _calculateExternalFees(State storage self, BalanceDelta result)
        internal
        view
        returns (FeeAmounts memory fees)
    {
        int128 amount0 = result.amount0();
        int128 amount1 = result.amount1();

        Slot0 memory slot0Cache = self.slot0;
        uint24 hookFees = slot0Cache.hookFees;
        uint24 protocolFees = slot0Cache.protocolFees;

        uint16 hookFee0 = getWithdrawFee(hookFees) % 64;
        uint16 hookFee1 = getWithdrawFee(hookFees) >> 6;

        uint16 protocolFee0 = getWithdrawFee(protocolFees) % 64;
        uint16 protocolFee1 = getWithdrawFee(protocolFees) >> 6;

        if (amount0 < 0 && hookFee0 > 0) {
            fees.feeForHook0 = uint128(-amount0) / hookFee0;
        }
        if (amount1 < 0 && hookFee1 > 0) {
            fees.feeForHook1 = uint128(-amount1) / hookFee1;
        }

        // A protocol fee is only applied if the hook fee is applied.
        if (protocolFee0 > 0 && fees.feeForHook0 > 0) {
            fees.feeForProtocol0 = fees.feeForHook0 / protocolFee0;
            fees.feeForHook0 -= fees.feeForProtocol0;
        }

        if (protocolFee1 > 0 && fees.feeForHook1 > 0) {
            fees.feeForProtocol1 = fees.feeForHook1 / protocolFee1;
            fees.feeForHook1 -= fees.feeForProtocol1;
        }

        return fees;
    }

    struct SwapCache {
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the protocol fee for the input token
        uint16 protocolFee;
        // the hook fee for the input token
        uint16 hookFee;
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
        returns (BalanceDelta result, uint256 feeForProtocol, uint256 feeForHook, SwapState memory state)
    {
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();

        Slot0 memory slot0Start = self.slot0;
        if (slot0Start.sqrtPriceX96 == 0) revert PoolNotInitialized();
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
            protocolFee: params.zeroForOne
                ? (getSwapFee(slot0Start.protocolFees) % 64)
                : (getSwapFee(slot0Start.protocolFees) >> 6),
            hookFee: params.zeroForOne ? (getSwapFee(slot0Start.hookFees) % 64) : (getSwapFee(slot0Start.hookFees) >> 6)
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

            if (cache.hookFee > 0) {
                // step.feeAmount has already been updated to account for the protocol fee
                uint256 delta = step.feeAmount / cache.hookFee;
                unchecked {
                    step.feeAmount -= delta;
                    feeForHook += delta;
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
    function donate(State storage state, uint256 amount0, uint256 amount1) internal returns (BalanceDelta delta) {
        if (state.liquidity == 0) revert NoLiquidityToReceiveFees();
        delta = toBalanceDelta(amount0.toInt128(), amount1.toInt128());
        unchecked {
            if (amount0 > 0) {
                state.feeGrowthGlobal0X128 += FullMath.mulDiv(amount0, FixedPoint128.Q128, state.liquidity);
            }
            if (amount1 > 0) {
                state.feeGrowthGlobal1X128 += FullMath.mulDiv(amount1, FixedPoint128.Q128, state.liquidity);
            }
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
        int24 tickCurrent = self.slot0.tick;

        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
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
