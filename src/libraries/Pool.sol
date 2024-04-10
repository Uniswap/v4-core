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
import {ProtocolFeeLibrary} from "./ProtocolFeeLibrary.sol";
import {LiquidityMath} from "./LiquidityMath.sol";

library Pool {
    using SafeCast for *;
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Pool for State;
    using ProtocolFeeLibrary for uint24;

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

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // protocol swap fee, taken as a % of the LP swap fee
        // upper 12 bits are for 1->0, and the lower 12 are for 0->1
        // the maximum is 2500 - meaning the maximum protocol fee is 25%
        uint24 protocolFee;
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

    function initialize(State storage self, uint160 sqrtPriceX96, uint24 protocolFee, uint24 swapFee)
        internal
        returns (int24 tick)
    {
        if (self.slot0.sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        self.slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, protocolFee: protocolFee, swapFee: swapFee});
    }

    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        if (self.isNotInitialized()) revert PoolNotInitialized();

        self.slot0.protocolFee = protocolFee;
    }

    /// @notice Only dynamic fee pools may update the swap fee.
    function setSwapFee(State storage self, uint24 swapFee) internal {
        if (self.isNotInitialized()) revert PoolNotInitialized();
        self.slot0.swapFee = swapFee;
    }

    struct ModifyLiquidityParams {
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

    struct ModifyLiquidityState {
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
    /// @return delta the deltas of the token balances of the pool, from the liquidity change
    /// @return feeDelta the fees generated by the liquidity range
    function modifyLiquidity(State storage self, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta, BalanceDelta feeDelta)
    {
        int128 liquidityDelta = params.liquidityDelta;
        int24 tickLower = params.tickLower;
        int24 tickUpper = params.tickUpper;
        checkTicks(tickLower, tickUpper);

        uint256 feesOwed0;
        uint256 feesOwed1;
        {
            ModifyLiquidityState memory state;

            // if we need to update the ticks, do it
            if (liquidityDelta != 0) {
                (state.flippedLower, state.liquidityGrossAfterLower) =
                    updateTick(self, tickLower, liquidityDelta, false);
                (state.flippedUpper, state.liquidityGrossAfterUpper) = updateTick(self, tickUpper, liquidityDelta, true);

                // `>` and `>=` are logically equivalent here but `>=` is cheaper
                if (liquidityDelta >= 0) {
                    uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                    if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                        revert TickLiquidityOverflow(tickLower);
                    }
                    if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                        revert TickLiquidityOverflow(tickUpper);
                    }
                }

                if (state.flippedLower) {
                    self.tickBitmap.flipTick(tickLower, params.tickSpacing);
                }
                if (state.flippedUpper) {
                    self.tickBitmap.flipTick(tickUpper, params.tickSpacing);
                }
            }

            (state.feeGrowthInside0X128, state.feeGrowthInside1X128) = getFeeGrowthInside(self, tickLower, tickUpper);

            Position.Info storage position = self.positions.get(params.owner, tickLower, tickUpper);
            (feesOwed0, feesOwed1) =
                position.update(liquidityDelta, state.feeGrowthInside0X128, state.feeGrowthInside1X128);

            // clear any tick data that is no longer needed
            if (liquidityDelta < 0) {
                if (state.flippedLower) {
                    clearTick(self, tickLower);
                }
                if (state.flippedUpper) {
                    clearTick(self, tickUpper);
                }
            }
        }

        if (liquidityDelta != 0) {
            int24 tick = self.slot0.tick;
            uint160 sqrtPriceX96 = self.slot0.sqrtPriceX96;
            if (tick < tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
                    ).toInt128(),
                    0
                );
            } else if (tick < tickUpper) {
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta)
                        .toInt128(),
                    SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(tickLower), sqrtPriceX96, liquidityDelta)
                        .toInt128()
                );

                self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
                delta = toBalanceDelta(
                    0,
                    SqrtPriceMath.getAmount1Delta(
                        TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta
                    ).toInt128()
                );
            }
        }

        // Fees earned from LPing are added to the user's currency delta.
        feeDelta = toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
    }

    struct SwapCache {
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the protocol fee for the input token
        uint16 protocolFee;
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
        bool zeroForOne = params.zeroForOne;
        if (zeroForOne) {
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
            protocolFee: zeroForOne ? slot0Start.protocolFee.getZeroForOneFee() : slot0Start.protocolFee.getOneForZeroFee()
        });

        bool exactInput = params.amountSpecified < 0;

        state = SwapState({
            amountSpecifiedRemaining: params.amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
            liquidity: cache.liquidityStart
        });

        StepComputations memory step;
        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != params.sqrtPriceLimitX96) {
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                self.tickBitmap.nextInitializedTickWithinOneWord(state.tick, params.tickSpacing, zeroForOne);

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
                    zeroForOne
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
                    state.amountSpecifiedRemaining += (step.amountIn + step.feeAmount).toInt256();
                }
                state.amountCalculated = state.amountCalculated + step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining -= step.amountOut.toInt256();
                }
                state.amountCalculated = state.amountCalculated - (step.amountIn + step.feeAmount).toInt256();
            }

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.protocolFee > 0) {
                // calculate the amount of the fee that should go to the protocol
                uint256 delta = step.feeAmount * cache.protocolFee / ProtocolFeeLibrary.BIPS_DENOMINATOR;
                // subtract it from the regular fee and add it to the protocol fee
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
                        (zeroForOne ? state.feeGrowthGlobalX128 : self.feeGrowthGlobal0X128),
                        (zeroForOne ? self.feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                unchecked {
                    state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
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
        if (zeroForOne) {
            self.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            self.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        unchecked {
            if (zeroForOne == exactInput) {
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
        delta = toBalanceDelta(-(amount0.toInt128()), -(amount1.toInt128()));
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

        liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

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
