import "./PoolManager.spec";

use invariant liquidityGrossNetInvariant filtered{f -> isModifyLiquidity(f)}
use invariant ValidTickAndPrice filtered{f -> isModifyLiquidity(f)}
use invariant NoGrossLiquidityForUninitializedTick filtered{f -> isModifyLiquidity(f)}
use invariant InitializedPoolHasValidTickSpacing filtered{f -> isModifyLiquidity(f)}

methods {
    /// Summarize to avoid BV theory by forcing the reverse operation to be equal to the input.
    /// For an unknown reason, this is the correct declaration prefix.
    function ERC6909.toBalanceDelta(int128 x, int128 y) internal returns (PoolManager.BalanceDelta) => toBalanceDeltaCVL(x,y);
}

function toBalanceDeltaCVL(int128 x, int128 y) returns PoolManager.BalanceDelta {
    PoolManager.BalanceDelta delta;
    require CurrencyGetters.amount0(delta) == x;
    require CurrencyGetters.amount1(delta) == y;
    return delta;
}

/// @title: The only function which can change a position liquidity is modifyLiquidity()
rule onlyModifyLiquidityChangesPositionLiquidity(method f) filtered{f -> !f.isView && !isUnlock(f)} {
    PoolManager.PoolId poolId;
    bytes32 positionId;

    uint128 liquidity_pre = getPositionLiquidityExt(poolId, positionId);
        env e;
        calldataarg args;
        f(e,args);
    uint128 liquidity_post = getPositionLiquidityExt(poolId, positionId);

    assert liquidity_pre != liquidity_post => isModifyLiquidity(f);
}

/// @title modifyLiquidity changes the correct position only, based on function input and the msg.sender.
rule modifyLiquidityPositionChangesCorrectly(PoolManager.PoolId poolId) {
    int24 tickLower;
    int24 tickUpper;
    bytes32 salt;
    address owner;
    bytes32 positionId = PoolGetters.getPositionKey(owner, tickLower, tickUpper, salt);

    uint128 liquidity_pre = getPositionLiquidityExt(poolId, positionId);
        
        env e;
        PoolManager.PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        modifyLiquidity(e, key, params, hookData);

        bool match = 
            PoolGetters.toId(key) == poolId &&
            params.tickLower == tickLower &&
            params.tickUpper == tickUpper &&
            params.salt == salt &&
            owner == e.msg.sender;
    
    uint128 liquidity_post = getPositionLiquidityExt(poolId, positionId);

    assert match => liquidity_post - liquidity_pre == params.liquidityDelta;
    assert !match => liquidity_post == liquidity_pre;
    satisfy match;
}

/// @title Only the msg.sender can change his own position liquidity.
rule liquidityChangedByOwnerOnly(address owner, PoolManager.PoolId poolId) {
    env e;
    int24 tickLower;
    int24 tickUpper;
    bytes32 salt;
    bytes32 positionId = PoolGetters.getPositionKey(owner,tickLower,tickUpper,salt);
    
    uint128 liquidity_pre = getPositionLiquidityExt(poolId, positionId);
        PoolManager.PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        PoolManager.PoolId modifyId = PoolGetters.toId(key);
        modifyLiquidity(e, key, params, hookData);
    uint128 liquidity_post = getPositionLiquidityExt(poolId, positionId);

    assert liquidity_pre != liquidity_post => owner == e.msg.sender;
    assert poolId != modifyId => liquidity_pre == liquidity_post;
    satisfy liquidity_pre != liquidity_post;
}

/// @title The change of position liquidity resulting delta preserves the total position funds.
rule changeOfLiquidityPreservesFunds(uint128 oldLiquidity, IPoolManager.ModifyLiquidityParams params) 
{
    require isValidTick(params.tickLower);
    require isValidTick(params.tickUpper);
    
    PoolManager.PoolKey key;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    requireInvariant ValidTickAndPrice(poolId);
    require isPoolInitialized(poolId);
    int24 tick = PoolGetters.getTick(poolId);
    uint160 sqrtPrice = PoolGetters.getSqrtPriceX96(poolId);
    uint128 newLiquidity = require_uint128(oldLiquidity + params.liquidityDelta);

    mathint amount0_old; mathint amount1_old;
    amount0_old, amount1_old = getPositionFunds(assert_int256(-oldLiquidity), params.tickLower, params.tickUpper, tick, sqrtPrice);
    /*
    env e;
    PoolManager.BalanceDelta callerDelta;
    PoolManager.BalanceDelta feesDelta;
    bytes hookData;
        callerDelta, feesDelta = modifyLiquidity(e, key, params, hookData);
    /// Principal tokens delta.
    mathint principal0 = CurrencyGetters.amount0(callerDelta) - CurrencyGetters.amount0(feesDelta);
    mathint principal1 = CurrencyGetters.amount1(callerDelta) - CurrencyGetters.amount1(feesDelta);
    */
    /// Returns absolute value of position deltas.
    mathint principal0; mathint principal1;
    principal0, principal1 = getPositionFunds(params.liquidityDelta, params.tickLower, params.tickUpper, tick, sqrtPrice);
    
    mathint amount0_new; mathint amount1_new;
    amount0_new, amount1_new = getPositionFunds(assert_int256(-newLiquidity), params.tickLower, params.tickUpper, tick, sqrtPrice);

    if(params.liquidityDelta > 0) {
        /// When delta is positive (deposit), principals are negative (because one has to pay).
        /// Amount deposited is larger than the difference in position value.
        assert amount0_new <= amount0_old + principal0 + 1;
        assert amount1_new <= amount1_old + principal1 + 1;
    } else {
        /// When delta is negative (withdraw), principals are positive (because one is owed tokens).
        /// Amount withdrawan is smaller than the difference in position value.
        assert amount0_new <= amount0_old - principal0 + 1;
        assert amount1_new <= amount1_old - principal1 + 1;
    }
}

/// @title The modifyLiquidity() returns deltas which match the position funds function.
rule modifyLiquidityReturnsPositionFunds() 
{
    env e;
    PoolManager.PoolKey key;
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    IPoolManager.ModifyLiquidityParams params;
    bytes hookData;

    uint160 SqrtPriceX96 = PoolGetters.getSqrtPriceX96(poolId);
    int24 tickCurrent = PoolGetters.getTick(poolId);
    bool depositOrWithdraw = params.liquidityDelta > 0;
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    /// We care only about hook-free deltas.
    require !CVLHasPermission(key.hooks, AFTER_REMOVE_LIQUIDITY_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_ADD_LIQUIDITY_FLAG());

    mathint funds0; mathint funds1;
    funds0, funds1 = getPositionFunds(
        params.liquidityDelta, 
        params.tickLower, 
        params.tickUpper,
        tickCurrent,
        SqrtPriceX96
    );
   
    PoolManager.BalanceDelta callerDelta;
    PoolManager.BalanceDelta feesDelta;
        callerDelta, feesDelta = modifyLiquidity(e, key, params, hookData);

    /// Total funds accrued (fees + position).
    mathint totalCaller0 = CurrencyGetters.amount0(callerDelta);
    mathint totalCaller1 = CurrencyGetters.amount1(callerDelta);
    /// Only accrued fees.
    mathint feesAccrued0 = CurrencyGetters.amount0(feesDelta);
    mathint feesAccrued1 = CurrencyGetters.amount1(feesDelta);

    assert (totalCaller0 - feesAccrued0) == (depositOrWithdraw ? -funds0 : funds0);
    assert (totalCaller1 - feesAccrued1) == (depositOrWithdraw ? -funds1 : funds1);
}

/// @title modifyLiquidity() correctly updates the total active liquidity if the positon is active or not.
rule activeLiquidityIsUpdatedCorrectlyModifyLiquidity(PoolManager.PoolKey key) {
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    IPoolManager.ModifyLiquidityParams params;
    uint160 SqrtPriceX96 = PoolGetters.getSqrtPriceX96(poolId);
    int24 tickCurrent = PoolGetters.getTick(poolId);

    PoolManager.PoolId poolId0;
    int24 tick0;

    uint128 liquidity_pre = getActiveLiquidity(poolId);
    mathint total_liquidity_upper_pre = total_liquidity_upper[poolId0][tick0];
    mathint total_liquidity_lower_pre = total_liquidity_lower[poolId0][tick0];
        env e;
        matchPositionKeyToTicks(params, e.msg.sender);
        bytes hookData;
        modifyLiquidity(e, key, params, hookData);
    uint128 liquidity_post = getActiveLiquidity(poolId);
    mathint total_liquidity_upper_post = total_liquidity_upper[poolId0][tick0];
    mathint total_liquidity_lower_post = total_liquidity_lower[poolId0][tick0];

    if(isActivePosition(params.tickLower, params.tickUpper, tickCurrent)) {
        assert liquidity_post - liquidity_pre == params.liquidityDelta;
    } else {
        assert liquidity_post == liquidity_pre;
    }

    if(poolId0 != poolId) {
        assert total_liquidity_upper_pre == total_liquidity_upper_post;
        assert total_liquidity_lower_pre == total_liquidity_lower_post;
    } else {
        if(tick0 == params.tickUpper) {
            assert total_liquidity_upper_post - total_liquidity_upper_pre == params.liquidityDelta;
        } else {
            assert total_liquidity_upper_pre == total_liquidity_upper_post;
        }

        if(tick0 == params.tickLower) {
            assert total_liquidity_lower_post - total_liquidity_lower_pre == params.liquidityDelta;
        } else {
            assert total_liquidity_lower_pre == total_liquidity_lower_post;
        }
    }
}

/// @title The underlying funds of the entire liquidity in a tick range exceeds the the sum of funds for all positions in a tick.
/// By induction, this is true, for a sum of any number of arbitrary positions.
rule fundsOfTotalLiquidityExceedsSumOfPositionFunds(PoolManager.PoolId poolId, int24 tickLower, int24 tickUpper) {
    uint160 SqrtPriceX96 = PoolGetters.getSqrtPriceX96(poolId);
    int24 tickCurrent = PoolGetters.getTick(poolId);
    requireInvariant ValidTickAndPrice(poolId);
    require isPoolInitialized(poolId);
    require isValidTick(tickLower);
    require isValidTick(tickUpper);
    require tickLower <= tickUpper;
    
    uint128 liquidityA;
    uint128 liquidityB;
    uint128 sumLiquidity = require_uint128(liquidityA + liquidityB);
    uint128 totalLiquidity;
    /// Explicit axiom - sometimes need to help the grounding.
    require forall uint160 sqrtA. forall uint160 sqrtB.
        sumLiquidity < totalLiquidity =>
        amount0Delta(sqrtA, sqrtB, sumLiquidity, false) <= amount0Delta(sqrtA, sqrtB, totalLiquidity, false) 
        &&
        amount1Delta(sqrtA, sqrtB, sumLiquidity, false) <= amount1Delta(sqrtA, sqrtB, totalLiquidity, false);
    
    mathint amount0_A; mathint amount1_A;
    amount0_A, amount1_A = getPositionFunds(assert_int256(-liquidityA), tickLower, tickUpper, tickCurrent, SqrtPriceX96);
    mathint amount0_B; mathint amount1_B;
    amount0_B, amount1_B = getPositionFunds(assert_int256(-liquidityB), tickLower, tickUpper, tickCurrent, SqrtPriceX96);
    mathint amount0_total; mathint amount1_total;
    amount0_total, amount1_total = getPositionFunds(assert_int256(-totalLiquidity), tickLower, tickUpper, tickCurrent, SqrtPriceX96);

    assert liquidityA + liquidityB <= totalLiquidity =>
        amount0_A + amount0_B <= amount0_total && amount1_A + amount1_B <= amount1_total;
}