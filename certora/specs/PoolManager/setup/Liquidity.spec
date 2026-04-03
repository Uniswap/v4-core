import "../../Common/TickMathDefinitions.spec";
import "../../Summaries/SqrtPriceMathRealSummary.spec";

definition min(int24 a, int24 b) returns int24 = a > b ? b : a;
definition max(int24 a, int24 b) returns int24 = a > b ? a : b;
definition abs(mathint a) returns mathint =  a > 0 ? a : -a;

/// The sum of liquidites from all positions for pool [poolId], whose upper tick is [tick].
/// Equivalent to positions in ticks: [MIN_TICK(), tick]
ghost mapping(PoolManager.PoolId => mapping(int24 => mathint)) total_liquidity_upper {
    init_state axiom forall PoolManager.PoolId poolId. forall int24 tick. 
        total_liquidity_upper[poolId][tick] == 0;
    axiom forall PoolManager.PoolId poolId. forall int24 tick. total_liquidity_upper[poolId][tick] >= 0;
}

/// The sum of liquidites from all positions for pool [poolId], whose lower tick is [tick].
/// Equivalent to positions in ticks: [tick, MAX_TICK()]
ghost mapping(PoolManager.PoolId => mapping(int24 => mathint)) total_liquidity_lower {
    init_state axiom forall PoolManager.PoolId poolId. forall int24 tick. 
        total_liquidity_lower[poolId][tick] == 0;
    axiom forall PoolManager.PoolId poolId. forall int24 tick. total_liquidity_lower[poolId][tick] >= 0;
}

/// Inverse hash of positionID to position ticks.
persistent ghost posLowerTick(bytes32) returns int24;
persistent ghost posUpperTick(bytes32) returns int24;

hook Sstore PoolManager._pools[KEY PoolManager.PoolId poolId].positions[KEY bytes32 positionKey].liquidity uint128 newLiquidity (uint128 oldLiquidity) {
    int24 tickLower = posLowerTick(positionKey);
    int24 tickUpper = posUpperTick(positionKey);

    total_liquidity_upper[poolId][tickUpper] =
    total_liquidity_upper[poolId][tickUpper] + newLiquidity - oldLiquidity;

    total_liquidity_lower[poolId][tickLower] =
    total_liquidity_lower[poolId][tickLower] + newLiquidity - oldLiquidity;
}

invariant liquidityGrossNetInvariant(PoolManager.PoolId poolId) 
    forall int24 tick.
        PoolManager._pools[poolId].ticks[tick].liquidityGross == total_liquidity_lower[poolId][tick] + total_liquidity_upper[poolId][tick] 
        &&
        PoolManager._pools[poolId].ticks[tick].liquidityNet == total_liquidity_lower[poolId][tick] - total_liquidity_upper[poolId][tick]
        &&
        (PoolManager._pools[poolId].ticks[tick].liquidityGross == 0 => PoolManager._pools[poolId].ticks[tick].liquidityNet == 0)
        {
            preserved modifyLiquidity(
            PoolManager.PoolKey key,
            IPoolManager.ModifyLiquidityParams params,
            bytes data
        ) with (env e) {
            matchPositionKeyToTicks(params, e.msg.sender);
            require PoolManager._pools[poolId].ticks[params.tickLower].liquidityNet == 
                total_liquidity_lower[poolId][params.tickLower] - total_liquidity_upper[poolId][params.tickLower];
            require PoolManager._pools[poolId].ticks[params.tickUpper].liquidityNet == 
                total_liquidity_lower[poolId][params.tickUpper] - total_liquidity_upper[poolId][params.tickUpper];
        }
        }

/// @title There are no positions with equal ticks at the bounds (true for any tick in general).
invariant NoLiquidityAtBounds(PoolManager.PoolId poolId)
    total_liquidity_lower[poolId][MAX_TICK()] == 0 && 
    total_liquidity_upper[poolId][MIN_TICK()] == 0
    {
        preserved modifyLiquidity(
            PoolManager.PoolKey key,
            IPoolManager.ModifyLiquidityParams params,
            bytes data
        ) with (env e) {
            matchPositionKeyToTicks(params, e.msg.sender);
        }
    }

/// Forces the ghost inverse hashing to match the position ID calculation.
function matchPositionKeyToTicks(IPoolManager.ModifyLiquidityParams params, address owner) {
    bytes32 positionId = PoolGetters.getPositionKey(owner, params.tickLower, params.tickUpper, params.salt);
    require posLowerTick(positionId) == params.tickLower;
    require posUpperTick(positionId) == params.tickUpper;
}

definition liquidityGross(PoolManager.PoolId poolId, int24 tick) returns mathint =
    total_liquidity_lower[poolId][tick] + total_liquidity_upper[poolId][tick];

definition liquidityNet(PoolManager.PoolId poolId, int24 tick) returns mathint =
    total_liquidity_lower[poolId][tick] - total_liquidity_upper[poolId][tick];

/*
Returns the outstanding funds of a liquidity position (liquidity, tickLower, tickUpper) for a pool at a state price = currentPrice.
returns (token0 amount, token1 amount)

notation:
P0 = current price
PL = sqrt(lower tick price)
PU = sqrt(upper tick price)
L = liquidity amount


Funds(L)     |       token0      |      token1      |
_____________|___________________|__________________|
             |                   |                  |
tick < lower | amount0(PL,PU,L)  |         0        |
             |                   |                  |
_____________|___________________|__________________|
             |                   |                  |
tick < Upper | amount0(P0,PU,L)  | amount1(PL,P0,L) |
             |                   |                  |
_____________|___________________|__________________|
             |                   |                  |
tick >= Upper|         0         | amount1(PL,PU,L) |
             |                   |                  |
_____________|___________________|__________________|
*/


definition isActivePosition(int24 tickLower, int24 tickUpper, int24 tickCurrent) returns bool = 
    tickCurrent >= tickLower && tickUpper > tickCurrent;

function getPositionFunds(int256 liquidityDelta, int24 tickLower, int24 tickUpper, int24 tickCurrent, uint160 sqrtP0) returns (uint128,uint128) {    
    bool depositOrWithdraw = liquidityDelta > 0;
    uint128 liquidity = depositOrWithdraw ? require_uint128(liquidityDelta) : require_uint128(-liquidityDelta);
    
    uint160 sqrtPL = sqrtPriceAtTick(tickLower);
    uint160 sqrtPU = sqrtPriceAtTick(tickUpper);

    uint160 sqrtQ0 = tickCurrent >= tickLower ? sqrtP0 : sqrtPL;
    uint160 sqrtQ1 = tickCurrent < tickUpper ? sqrtP0 : sqrtPU;

    mathint amount0 = tickCurrent >= tickUpper 
        ? 0 : amount0Delta(sqrtPU, sqrtQ0, liquidity, depositOrWithdraw);

    mathint amount1 = tickCurrent < tickLower 
        ? 0 : amount1Delta(sqrtPL, sqrtQ1, liquidity, depositOrWithdraw);

    return (require_uint128(amount0), require_uint128(amount1));
}
