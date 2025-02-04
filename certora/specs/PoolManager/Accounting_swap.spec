/* =======================================================
The amount0/amount1 axioms show that any position funds (round-down) in ticks [tickLower,tickUpper) satisfy:

funds(tickLower, tickUpper, L) <= funds(tickLower, MAX_TICK(), L) - funds(tickUpper, MAX_TICK(), L) = 
    funds(total_liquidity_lower(tickLower)) - funds(total_liquidity_lower(tickUpper)) = 

and also:

funds(tickLower, tickUpper, L) <= funds(MIN_TICK(), tickUpper, L) - funds(MIN_TICK(), tickLower, L) =
    funds(total_liquidity_upper(tickUpper)) - funds(total_liquidity_upper(tickLower)) = 


If we consider only active positions funds, then tickLower <= current tick < tickUpper.

During a swap, 
    if the tick moves to the right (zeroForOne = false) then funds(MIN_TICK(), tickLower, L) doesn't change.
    and if the tick moves to the left (zeroForOne = true) then funds(tickUpper, MAX_TICK(), L) doesn't change.

Considering (zeroForOne = false) case:
    Then pool tick before <= pool tick after. 
    Value of funds(MIN_TICK(), tickLower, L) doesn't change
    Value of funds(MAX_TICK(), tickUpper, L) could have two outcomes
        A. if pool tick after swap doesn't cross tickUpper of the position, then the difference in funds are
            amount0Delta(sqrtPrice_before, MAX_SQRT_PRICE, liquidity) - amount0Delta(sqrtPrice_after, MAX_SQRT_PRICE, liquidity)
            <= amount0Delta(sqrtPrice_before, sqrtPrice_after, liquidity) + 1

        B. if pool tick after swap reaches the tickUpper of the position, then we know that there
            are no initialized ticks that were skipped, and the next tick is the closest tick with liquidity in it (the closest initialized).
            Then this (next) tick holds two types of liquidites who change their status:
            - (MIN_TICK, next_tick) - from active become inactive - liquidity amount is total_liquidity_upper[next_tick].
            - (next_tick, MAX_TICK) - from inactive become active - liquidity amount is total_liquidity_lower[next_tick].

            The delta of active liquidity between those two positions is total_liquidity_lower[next_tick] - total_liquidity_upper[next_tick]
            = liquidityNet[next_tick] ! 
======================================================= */
import "./PoolManager.spec";
/// Use this summary to replace the real Slot0 library with CVL mapping implementation (verified).
/// Significantly improves running times for swap().
import "../Summaries/Slot0Summary.spec";

use rule swapIntegrity;
use invariant LiquidityGrossBound filtered{f -> isSwap(f)}
use invariant NoLiquidityAtBounds filtered{f -> isSwap(f)}
use invariant OnlyAlignedTicksPositions filtered{f -> isSwap(f)}
use invariant liquidityGrossNetInvariant filtered{f -> isSwap(f)}
use invariant ValidSwapFee filtered{f -> isSwap(f)}
use invariant ValidTickAndPrice filtered{f -> isSwap(f)}
use invariant NoGrossLiquidityForUninitializedTick filtered{f -> isSwap(f)}
use invariant InitializedPoolHasValidTickSpacing filtered{f -> isSwap(f)}
use invariant TickSqrtPriceCorrelation filtered{f -> isSwap(f)}
use invariant TickSqrtPriceStrongCorrelation filtered{f -> isSwap(f)}

/* =======================================================
/// Helper ghost for tracking of crossing a tick - WE ASSUME
/// that any cross of a tick in swap() involves a Sstore op to ticks[tick].feeGrowthOutside0X128/1X128.
*/

ghost mapping(int24 => bool) tick_was_crossed;
ghost mathint net_liquidity_crossed;

hook Sstore PoolManager._pools[KEY PoolManager.PoolId poolId].ticks[KEY int24 tick].feeGrowthOutside0X128 uint256 value_new (uint256 value_old) {
    if(!tick_was_crossed[tick]) {
        net_liquidity_crossed = net_liquidity_crossed + PoolManager._pools[poolId].ticks[tick].liquidityNet;
        tick_was_crossed[tick] = true;
    }
}

hook Sstore PoolManager._pools[KEY PoolManager.PoolId poolId].ticks[KEY int24 tick].feeGrowthOutside1X128 uint256 value_new (uint256 value_old) {
    if(!tick_was_crossed[tick]) {
        net_liquidity_crossed = net_liquidity_crossed + PoolManager._pools[poolId].ticks[tick].liquidityNet;
        tick_was_crossed[tick] = true;
    }
}

/// Auxiliary rule
/// @title If the tick of the pool didn't change, then no tick was crossed.
/// If any tick was crossed, it must be between the pre and the post-swap ticks.
rule integrityOfCrossingTicks(int24 tick) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolGetters.PoolId poolId = PoolGetters.toId(key);
    require poolId == bitmapPoolId;
    /// Initialize crossed state to false. 
    require forall int24 tick_. !tick_was_crossed[tick_];

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);

    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId);
        swap(e, key, params, hooks);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_post = PoolGetters.getTick(poolId);

    assert (tick_pre == tick_post) => !tick_was_crossed[tick];
    if(params.zeroForOne) {
        assert tick_was_crossed[tick] => tick_post <= tick && tick <= tick_pre;
    } else {
        assert tick_was_crossed[tick] => tick_pre <= tick && tick <= tick_post;
    }
}



/// Sometimes the quantified axiom grounding doesn't take effect for all combinations.
/// In this case we specifically choose the arguments and apply the axiom, based on rule assertion.
function applySqrtPriceAdditivityAxiomRoundDown(uint128 liquidity, uint160 sqrtP, uint160 sqrtQ, uint160 sqrtR) 
{
    require
    (sqrtP <= sqrtQ && sqrtQ <= sqrtR && isValidSqrt(sqrtP) && isValidSqrt(sqrtR)) => (
         // Additivity:
        GreaterUpTo(
            amount0Delta(sqrtP, sqrtR, liquidity, false),
            amount0Delta(sqrtP, sqrtQ, liquidity, false) + 
            amount0Delta(sqrtQ, sqrtR, liquidity, false),
            1
        )
        &&
        GreaterUpTo(
            amount1Delta(sqrtP, sqrtR, liquidity, false),
            amount1Delta(sqrtP, sqrtQ, liquidity, false) + 
            amount1Delta(sqrtQ, sqrtR, liquidity, false),
            1
        )
        &&
        // Monotonicity:
        amount0Delta(sqrtP, sqrtR, liquidity, false) >= amount0Delta(sqrtP, sqrtQ, liquidity, false)
        &&
        amount1Delta(sqrtP, sqrtR, liquidity, false) >= amount1Delta(sqrtP, sqrtQ, liquidity, false)
    );
}

/// @title If a position remains inactive during a swap (without being crossed), its underlying funds must stay intact.
rule inactivePositionFundsDontChangeAfterSwap() {
    //storage initState = lastStorage;

    //env e1;
    PoolManager.PoolKey key;
    IPoolManager.ModifyLiquidityParams params;
    bytes hookData;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    bitmapPoolId = poolId;

    /// Initialize crossed state to false. 
    require forall int24 tick_. !tick_was_crossed[tick_];

    int24 tick_pre = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant liquidityGrossNetInvariant(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);
    
    /// Valid position
    require params.tickUpper <= MAX_TICK();
    require params.tickLower >= MIN_TICK();
    require params.tickLower <= params.tickUpper;
    /// A non-empty position in the pool contributes to the total liquidity:
    require total_liquidity_lower[poolId][params.tickLower] > 0;
    require total_liquidity_upper[poolId][params.tickUpper] > 0;
    /// The position is inactive at the beginning.
    require !isActivePosition(params.tickLower, params.tickUpper, tick_pre);
    /*
    PoolManager.BalanceDelta callerDeltaA;
    PoolManager.BalanceDelta feesDeltaA;
        callerDeltaA, feesDeltaA = modifyLiquidity(e1, key, params, hookData) at initState;
    */

    mathint totalCaller0_A; mathint totalCaller1_A;
    totalCaller0_A, totalCaller1_A = getPositionFunds(params.liquidityDelta, params.tickLower, params.tickUpper, tick_pre, sqrtPrice_pre);

    env e2;
    IPoolManager.SwapParams swapParams; 
    bytes hooks;
    swap(e2, key, swapParams, hooks);
    
    int24 tick_post = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    /*
    PoolManager.BalanceDelta callerDeltaB;
    PoolManager.BalanceDelta feesDeltaB;
        callerDeltaB, feesDeltaB = modifyLiquidity(e1, key, params, hookData);
    */
    mathint totalCaller0_B; mathint totalCaller1_B;
    totalCaller0_B, totalCaller1_B = getPositionFunds(params.liquidityDelta, params.tickLower, params.tickUpper, tick_post, sqrtPrice_post);

    /// Total funds accrued
    /*
    mathint totalCaller0_A = CurrencyGetters.amount0(callerDeltaA);
    mathint totalCaller1_A = CurrencyGetters.amount1(callerDeltaA);
    mathint totalCaller0_B = CurrencyGetters.amount0(callerDeltaB);
    mathint totalCaller1_B = CurrencyGetters.amount1(callerDeltaB);
    */
    
    /// If all position ticks were not crossed during the swap, the position funds mustn't changed.
    assert ( 
        forall int24 tick_. (params.tickLower <= tick_ && tick_ <= params.tickUpper => !tick_was_crossed[tick_])
        ) => 
        totalCaller0_A == totalCaller0_B && totalCaller1_A == totalCaller1_B;
}

/// @title The total active liquidity is updated correctly by the sum of net liquidities of crossed ticks.
rule activeLiquidityUpdatedCorrectly {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    require bitmapPoolId == poolId;
    /// Initialize crossed liquidity.
    require net_liquidity_crossed == 0;
    require forall int24 tick_. !tick_was_crossed[tick_];
    
    /// requireInvariant LiquidityGrossBound
    require forall int24 tick. liquidityGrossBound(poolId, tick);
    requireInvariant liquidityGrossNetInvariant(poolId);

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant ValidSwapFee(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);
    requireInvariant NoLiquidityAtBounds(poolId);

    uint128 liquidity_pre = getActiveLiquidity(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
        swap(e, key, params, hooks);
    uint128 liquidity_post = getActiveLiquidity(poolId);
    int24 tick_post = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);

    assert liquidity_post - liquidity_pre == (params.zeroForOne ? -net_liquidity_crossed : net_liquidity_crossed);
}

/// @title The funds of any position could be broken into two positions, positive and negative, with a tick as a extremal tick.
rule positionExtremalTickSeparation(uint128 liquidity, int24 tickLower, int24 tickUpper, bool zeroForOne) {
    /// Assume valid position
    require isValidTick(tickLower);
    require isValidTick(tickUpper);
    require tickLower <= tickUpper;
    uint160 sqrtL = sqrtPriceAtTick(tickLower);
    uint160 sqrtU = sqrtPriceAtTick(tickUpper);

    int24 tick;
    uint160 sqrtPrice;
    require isValidTick(tick);
    require isValidSqrt(sqrtPrice);
    require TickSqrtPriceCorrespondence(tick, sqrtPrice);
    
    mathint amount0; mathint amount1;
    /// Original position
    amount0, amount1 = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick, sqrtPrice);
    mathint amount0_L; mathint amount1_L;
    mathint amount0_U; mathint amount1_U;

    if(zeroForOne) {
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtL, sqrtU, MAX_SQRT_PRICE());
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtL, sqrtPrice, sqrtU);
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtU, sqrtPrice, MAX_SQRT_PRICE());

        amount0_L, amount1_L = getPositionFunds(assert_int256(-liquidity), tickLower, MAX_TICK(), tick, sqrtPrice);
        amount0_U, amount1_U = getPositionFunds(assert_int256(-liquidity), tickUpper, MAX_TICK(), tick, sqrtPrice);

        assert GreaterUpTo(amount0_L - amount0_U, amount0, 1);
        assert GreaterUpTo(amount1_L - amount1_U, amount1, 1);
    } else {
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, MIN_SQRT_PRICE(), sqrtL, sqrtU);
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtL, sqrtPrice, sqrtU);
        applySqrtPriceAdditivityAxiomRoundDown(liquidity, MIN_SQRT_PRICE(), sqrtL, sqrtU);

        amount0_L, amount1_L = getPositionFunds(assert_int256(-liquidity), MIN_TICK(), tickLower, tick, sqrtPrice);
        amount0_U, amount1_U = getPositionFunds(assert_int256(-liquidity), MIN_TICK(), tickUpper, tick, sqrtPrice);

        assert GreaterUpTo(amount0_U - amount0_L, amount0, 1);
        assert GreaterUpTo(amount1_U - amount1_L, amount1, 1);
    }
}

/// @title When swapping to the right, inactive positions to the left don't change their value.
rule positionsToTheLeftDontChangeValue(uint128 liquidity, int24 tickLower, int24 tickUpper) {
    /// Swap parameters
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    require bitmapPoolId == poolId;
    require params.zeroForOne == false;
    require isPoolInitialized(poolId);
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    /// Assume valid position
    require isValidTick(tickLower);
    require isValidTick(tickUpper);
    require tickLower <= tickUpper;

    int24 tick_pre = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_pre, sqrtPrice_pre);

        swap(e, key, params, hooks);

    int24 tick_post = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_post, sqrtPrice_post);

    assert tickUpper <= tick_pre => amount0_post == amount0_pre && amount1_post == amount1_pre;        
}

/// @title When swapping to the left, inactive positions to the right don't change their value.
rule positionsToTheRightDontChangeValue(uint128 liquidity, int24 tickLower, int24 tickUpper) {
    /// Swap parameters
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    require bitmapPoolId == poolId;
    require params.zeroForOne == true;
    require isPoolInitialized(poolId);
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    /// Assume valid position
    require isValidTick(tickLower);
    require isValidTick(tickUpper);
    require tickLower <= tickUpper;

    int24 tick_pre = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_pre, sqrtPrice_pre);

        swap(e, key, params, hooks);

    int24 tick_post = PoolGetters.getTick(poolId); 
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_post, sqrtPrice_post);

    assert tickLower > tick_pre => amount0_post == amount0_pre && amount1_post == amount1_pre;
}
/// @title When a tick shifts to the left (zeroForOne = true), positions funds with tickUpper = MAX_TICK() should change 
/// by the amount deltas of the prices before and after the shift. 
rule positionFundsChangeUponTickSlipMaxUpper(uint128 liquidity, int24 tickLower) 
{
    int24 tick_pre;
    uint160 sqrtPrice_pre;
    int24 tickUpper = MAX_TICK();
    require isValidTick(tickLower);
    require isValidTick(tick_pre);
    require isValidSqrt(sqrtPrice_pre);
    require isActivePosition(tickLower, tickUpper, tick_pre);
    require TickSqrtPriceCorrespondence(tick_pre, sqrtPrice_pre);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_pre, sqrtPrice_pre);
    bool isActiveBefore = isActivePosition(tickLower, tickUpper, tick_pre);

    int24 tick_post;
    uint160 sqrtPrice_post;
    require isValidTick(tick_post);
    require isValidSqrt(sqrtPrice_post);
    require TickSqrtPriceCorrespondence(tick_post, sqrtPrice_post);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_post, sqrtPrice_post);
    bool isActiveAfter = isActivePosition(tickLower, tickUpper, tick_post);

    /// zeroForOne = true;
    /// Verified by swapIntegrity
    require tick_pre >= tick_post;
    require sqrtPrice_pre >= sqrtPrice_post;
    applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtPrice_post, sqrtPrice_pre, MAX_SQRT_PRICE());
    applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtPrice_post, sqrtPrice_pre, sqrtPriceAtTick(tick_pre));
    
    if(sqrtPriceAtTick(tickLower) <= sqrtPrice_post) {
    /// All positions whose lower tick price is lower or equal to the price after swap.
        /// The gain in position value equals the difference in amount0Delta of the two prices.
        assert amount0_post - amount0_pre == amount0Delta(sqrtPrice_post, MAX_SQRT_PRICE(), liquidity, false) - amount0Delta(sqrtPrice_pre, MAX_SQRT_PRICE(), liquidity, false);
        /// The loss in position value must be bounded from below by the amount1Delta of the two prices.
        assert GreaterUpTo(amount1_pre - amount1_post, amount1Delta(sqrtPrice_post, sqrtPrice_pre, liquidity, false), 1);
    } else if(sqrtPriceAtTick(tickLower) >= sqrtPrice_pre) {
    /// All positions whose lower tick price is greater or equal to the price before the swap - remain inactive.
        assert amount0_post == amount0_pre;
        assert amount1_pre == amount1_pre;
    } else {
        /// That case is considered in 'swapping_doesnt_skip_liquidites_zeroForOne'.
        assert true;
    }
    assert !isActiveBefore => amount0_post == amount0_pre && amount1_pre == amount1_pre,
        "The funds of an inactive position cannot change after one swap iteration";
}

/// @title When a tick shifts to the right (zeroForOne = false), positions funds with tickLower = MIN_TICK() should change 
/// by the amount deltas of the prices before and after the shift. 
rule positionFundsChangeUponTickSlipMinLower(uint128 liquidity, int24 tickUpper) 
{
    int24 tick_pre;
    uint160 sqrtPrice_pre;
    int24 tickLower = MIN_TICK();
    require isValidTick(tickUpper);
    require isValidTick(tick_pre);
    require isValidSqrt(sqrtPrice_pre);
    require isActivePosition(tickLower, tickUpper, tick_pre);
    require TickSqrtPriceCorrespondence(tick_pre, sqrtPrice_pre);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_pre, sqrtPrice_pre);
    bool isActiveBefore = isActivePosition(tickLower, tickUpper, tick_pre);

    int24 tick_post;
    uint160 sqrtPrice_post;
    require isValidTick(tick_post);
    require isValidSqrt(sqrtPrice_post);
    require TickSqrtPriceCorrespondence(tick_post, sqrtPrice_post);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(assert_int256(-liquidity), tickLower, tickUpper, tick_post, sqrtPrice_post);
    bool isActiveAfter = isActivePosition(tickLower, tickUpper, tick_post);

    /// zeroForOne = false;
    /// Verified by swapIntegrity
    require tick_pre <= tick_post;
    require sqrtPrice_pre <= sqrtPrice_post;
    applySqrtPriceAdditivityAxiomRoundDown(liquidity, MIN_SQRT_PRICE(), sqrtPrice_pre, sqrtPrice_post);
    applySqrtPriceAdditivityAxiomRoundDown(liquidity, sqrtPrice_pre, sqrtPrice_post, sqrtPriceAtTick(tickUpper));

    if(sqrtPriceAtTick(tickUpper) >= sqrtPrice_post) {
    /// All positions whose upper tick price is greater or equal to the price after swap.
        /// The loss in position value must be bounded from below by the amount0Delta of the two prices.
        assert GreaterUpTo(amount0_pre - amount0_post, amount0Delta(sqrtPrice_pre, sqrtPrice_post, liquidity, false), 1);
        /// The gain in position value equals the difference in amount1Delta of the two prices.
        assert amount1_post - amount1_pre == amount1Delta(MIN_SQRT_PRICE(), sqrtPrice_post, liquidity, false) - amount1Delta(MIN_SQRT_PRICE(), sqrtPrice_pre, liquidity, false);
    } else if(sqrtPriceAtTick(tickUpper) <= sqrtPrice_pre) {
    /// All positions whose upper tick price is lower or equal to the price before the swap - remain inactive.
        assert amount0_post == amount0_pre;
        assert amount1_pre == amount1_pre;
    } else {
        /// That case is considered in 'swapping_doesnt_skip_liquidites_oneForZero'.
        assert true;
    }
    assert !isActiveBefore => amount0_post == amount0_pre && amount1_pre == amount1_pre,
        "The funds of an inactive position cannot change after one swap iteration";
}

/// @title The price transition during a swap (to left) cannot skip the price of any non-empty position boundary price.
rule swappingDoesntSkipLiquiditesZeroForOne(int24 tickUpper) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolGetters.PoolId poolId = PoolGetters.toId(key);
    require poolId == bitmapPoolId;
    /// Initialize crossed state to false. 
    require forall int24 tick_. !tick_was_crossed[tick_];
    /// Swapping to the left
    require params.zeroForOne == true;
    uint160 sqrtPriceU = sqrtPriceAtTick(tickUpper);

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);

    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId);
        swap(e, key, params, hooks);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_post = PoolGetters.getTick(poolId);

    assert (tick_pre != tick_post) => (
        (sqrtPriceU < sqrtPrice_pre && sqrtPriceU > sqrtPrice_post) =>
        (liquidityNet(poolId, tickUpper) == 0 || tick_was_crossed[tickUpper])
    ), "If the pool tick slipped, there cannot be any non-empty positions between the two prices";
    satisfy tick_was_crossed[tickUpper];
}

/// @title The price transition during a swap (to right) cannot skip the price of any non-empty position boundary price.
rule swappingDoesntSkipLiquiditesOneForZero(int24 tickLower) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolGetters.PoolId poolId = PoolGetters.toId(key);
    require poolId == bitmapPoolId;
    /// Initialize crossed state to false. 
    require forall int24 tick_. !tick_was_crossed[tick_];
    /// Swapping to the right
    require params.zeroForOne == false;
    uint160 sqrtPriceL = sqrtPriceAtTick(tickLower);

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);

    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId);
        swap(e, key, params, hooks);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_post = PoolGetters.getTick(poolId);

    assert (tick_pre != tick_post) => (
        (sqrtPriceL < sqrtPrice_post && sqrtPriceL > sqrtPrice_pre) =>
        (liquidityNet(poolId, tickLower) == 0 || tick_was_crossed[tickLower])
    ), "If the pool tick slipped, there cannot be any non-empty positions between the two prices";
}

/// @title The swap curreny deltas are bounded by the active liquidity change of funds during a price slip.
rule swapDeltasCoveredByAmountsDeltaOfActiveLiquidityZeroForOne() {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolGetters.PoolId poolId = PoolGetters.toId(key);
    /// Swapping to the left
    require params.zeroForOne == true;
    /// We only care about pure swap deltas.
    require !CVLHasPermission(key.hooks, BEFORE_SWAP_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_SWAP_FLAG());

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant ValidSwapFee(poolId);

    /// Initialize sum of funds ghosts
    sumOfAmounts0 = 0;
    sumOfAmounts1 = 0;

    uint128 liquidity_pre = getActiveLiquidity(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId);

        PoolManager.BalanceDelta swapDelta = swap(e, key, params, hooks);
        int128 swap0 = CurrencyGetters.amount0(swapDelta);
        int128 swap1 = CurrencyGetters.amount1(swapDelta);
    
    uint128 liquidity_post = getActiveLiquidity(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_post = PoolGetters.getTick(poolId);
    
    applySqrtPriceAdditivityAxiomRoundDown(liquidity_pre, sqrtPrice_post, sqrtPrice_pre, MAX_SQRT_PRICE());

    assert assert_uint256(-swap0) >= sumOfAmounts0,
        "The user must pay at least the increase in position token0 delta";
    assert assert_uint256(swap1) <= sumOfAmounts1,
        "The user cannot get more than the decrease in position token1 delta";
}

/// @title The swap curreny deltas are bounded by the active liquidity change of funds during a price slip.
rule swapDeltasCoveredByAmountsDeltaOfActiveLiquidityOneForZero() {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    PoolGetters.PoolId poolId = PoolGetters.toId(key);
    /// Swapping to the right
    require params.zeroForOne == false;
    /// We only care about pure swap deltas.
    require !CVLHasPermission(key.hooks, BEFORE_SWAP_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_SWAP_FLAG());

    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant ValidSwapFee(poolId);

    /// Initialize sum of funds ghosts
    sumOfAmounts0 = 0;
    sumOfAmounts1 = 0;

    uint128 liquidity_pre = getActiveLiquidity(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_pre = PoolGetters.getTick(poolId);

    PoolManager.BalanceDelta swapDelta = swap(e, key, params, hooks);
    int128 swap0 = CurrencyGetters.amount0(swapDelta);
    int128 swap1 = CurrencyGetters.amount1(swapDelta);

    uint128 liquidity_post = getActiveLiquidity(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    int24 tick_post = PoolGetters.getTick(poolId);

    /// Assumption : sqrtPriceMath axioms hold for on pre and post sqrt prices.
    applySqrtPriceAdditivityAxiomRoundDown(liquidity_pre, MIN_SQRT_PRICE(), sqrtPrice_pre, sqrtPrice_post);

    assert assert_uint256(-swap1) >= sumOfAmounts1,
        "The user must pay at least the increase in position token1 delta";
    assert assert_uint256(swap0) <= sumOfAmounts0,
        "The user cannot get more than the decrease in position token0 delta";
}
