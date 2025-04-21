import "../Summaries/TickMathSummary.spec";
import "../Summaries/UnsafeMathSummary.spec";
import "../Summaries/FullMathSummary.spec";
import "./setup/HooksNONDET.spec";
import "../Summaries/PoolStateTickBitmapMirror.spec";
import "../Summaries/CVLERC20.spec";
import "../Summaries/ProtocolFeeLibrary.spec";
import "./setup/extsload.spec";
import "./setup/lock.spec";
import "./setup/Liquidity.spec";
import "../Summaries/SwapStepSummary.spec";
/// Use this summary to replace the real Slot0 library with CVL mapping implementation (verified).
/// Significantly improves running times for swap().
/// import "../Summaries/Slot0Summary.spec";

using PoolManager as PoolManager;
using PoolGetters as PoolGetters;
using PoolTakeTest as CallbackTest;

methods {
    function PoolGetters.isUnlocked() external returns (bool) envfree;
    function PoolGetters.toId(PoolManager.PoolKey) external returns (PoolManager.PoolId) envfree;
    function PoolGetters.getNonzeroDeltaCount() external returns (uint256) envfree;
    function PoolGetters.currencyDelta(address,PoolManager.Currency) external returns (int256) envfree;
    function CurrencyGetters.amount0(PoolManager.BalanceDelta) external returns (int128) envfree;
    function CurrencyGetters.amount1(PoolManager.BalanceDelta) external returns (int128) envfree;
    function PoolGetters.getPositionKey(address,int24,int24,bytes32) external returns (bytes32) envfree;
    function protocolFeesAccrued(PoolManager.Currency) external returns (uint256) envfree;
    function ParseBytes.parseSelector(bytes memory) internal returns (bytes4) => NONDET;
}

use invariant nonZeroStart;
use invariant nonZeroMonotonousInvariant;
use invariant nonZeroCounterStepInvariant;
use invariant nonZeroCorrect;
use invariant isLockedAndDeltaZero;
use rule lockSanityCheck;
use builtin rule sanity;

/// Method filter for those that require the contract to be in the unlocked state.
definition mustBeUnlockedToCall(method f) returns bool = 
    f.selector == sig:burn(address,uint256,uint256).selector ||
    f.selector == sig:mint(address,uint256,uint256).selector ||
    f.selector == sig:settle().selector ||
    f.selector == sig:settleFor(address).selector ||
    f.selector == sig:take(PoolManager.Currency,address,uint256).selector ||
    f.selector == sig:swap(PoolManager.PoolKey,IPoolManager.SwapParams,bytes).selector ||
    f.selector == sig:donate(PoolManager.PoolKey,uint256,uint256,bytes).selector ||
    f.selector == sig:modifyLiquidity(PoolManager.PoolKey,IPoolManager.ModifyLiquidityParams,bytes).selector ||
    f.selector == sig:clear(PoolManager.Currency,uint256).selector;
    //|| f.selector == sig:sync(PoolManager.Currency).selector;

definition isModifyLiquidity(method f) returns bool = 
    f.selector == sig:modifyLiquidity(PoolManager.PoolKey,IPoolManager.ModifyLiquidityParams,bytes).selector;

definition isSwap(method f) returns bool = 
    f.selector == sig:swap(PoolManager.PoolKey,IPoolManager.SwapParams,bytes).selector;

definition isUnlock(method f) returns bool = 
    f.selector == sig:unlock(bytes).selector;

/// Require a batch of all strong locking invariants.
function requireLockingInvariants() {
    requireInvariant nonZeroCorrect();
    requireInvariant nonZeroCounterStepInvariant();
    requireInvariant nonZeroMonotonousInvariant();
    requireInvariant nonZeroStart();
}

/// @title Verifies that all filtered functions succeed only if the pool manager is unlocked.
rule mustUnlockToCall(method f) filtered{f -> mustBeUnlockedToCall(f)} {
    bool unlocked = PoolGetters.isUnlocked();
    env e;
    calldataarg args;
    f(e, args);
    assert unlocked;
}

/// @title Witness for all functions that can succeed when the pool manager is locked.
rule canBeCalledIfLocked(method f) filtered{f -> !mustBeUnlockedToCall(f)} {
    bool locked = !PoolGetters.isUnlocked();
    env e;
    calldataarg args;
    f(e, args);
    satisfy locked;
}

/// @title For any pool, the swap fee is correctly bounded.
invariant ValidSwapFee(PoolManager.PoolId id)
    PoolGetters.getLpFee(id) <= MAX_LP_FEE() && 
    isValidProtocolFee(PoolGetters.getProtocolFee(id))
    /// swap() doesn't change the Pool configured fees. See 'swapDoesntChangePoolFees'.
    /// Therefore, the invariant is preserved.
    filtered{f -> !isSwap(f)}

/// @title The net liquidity in any tick doesn't change when calling swap().
rule netLiquidityImmutableInSwap(PoolManager.PoolId poolId, int24 tick) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params; 
    bytes hooks;

    int128 liquidityNet_pre;
    _, liquidityNet_pre = getTickLiquidityExt(poolId, tick);
        swap(e, key, params, hooks);
    int128 liquidityNet_post;
    _, liquidityNet_post = getTickLiquidityExt(poolId, tick);

    assert liquidityNet_post == liquidityNet_pre;
}

/// @title Only the owner of a position may change its liquidity amount.
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

/// @title The sqrt price of a pool cannot turn from nonzero to zero.
rule poolSqrtPriceNeverTurnsZero(method f, PoolManager.PoolId id) filtered{f -> !f.isView} 
{    
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(id);
        env e;
        if(isSwap(f)) {
            PoolManager.PoolKey key;
            IPoolManager.SwapParams params; 
            bytes hooks;
            requireInvariant ValidTickAndPrice(PoolGetters.toId(key));
            swap(e, key, params, hooks);
        }
        else {
            calldataarg args;
            f(e, args);
        }
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(id);

    assert sqrtPrice_pre !=0 => sqrtPrice_post !=0;
}

/// @title Swapping doesn't change a pool's configuration fees.
rule swapDoesntChangePoolFees(PoolManager.PoolId id) {
    mathint LPFee_pre = PoolGetters.getLpFee(id);
    mathint ProtocolFee_pre = PoolGetters.getProtocolFee(id);
        env e;
        calldataarg args;
        swap(e, args);
    mathint LPFee_post = PoolGetters.getLpFee(id);
    mathint ProtocolFee_post = PoolGetters.getProtocolFee(id);

    assert LPFee_pre == LPFee_post;
    assert ProtocolFee_pre == ProtocolFee_post;
}

/// @title A witness for the change of a pool price after a swap.
rule swapPriceChangeWitness(PoolManager.PoolId id) {
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(id);
        env e;
        calldataarg args;
        swap(e, args);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(id);

    satisfy sqrtPrice_pre != sqrtPrice_post;
}

/// @title A witness for the change of currency deltas of two tokens after a swap.
rule swapTokensCurrencyDeltaChangeWitness(PoolManager.Currency tokenA, PoolManager.Currency tokenB) {
    env e;
    require e.msg.sender != PoolManager;
    mathint balanceA_pre = PoolGetters.currencyDelta(e.msg.sender, tokenA);
    mathint balanceB_pre = PoolGetters.currencyDelta(e.msg.sender, tokenB);
        calldataarg args;
        swap(e, args);
    mathint balanceA_post = PoolGetters.currencyDelta(e.msg.sender, tokenA);
    mathint balanceB_post = PoolGetters.currencyDelta(e.msg.sender, tokenB);

    satisfy tokenA != tokenB && balanceA_pre != balanceA_post && balanceB_pre != balanceB_post;
}

/// @title A witness for the change of currency deltas of two tokens after an unlock callback.
rule unlockTokensBalanceChangeWitness(address tokenA, address tokenB) {
    env e;
    require e.msg.sender != PoolManager;
    mathint balanceA_pre = tokenBalanceOf(tokenA, e.msg.sender);
    mathint balanceB_pre = tokenBalanceOf(tokenB, e.msg.sender);
        bytes data;
        unlock(e, data);
    mathint balanceA_post = tokenBalanceOf(tokenA, e.msg.sender);
    mathint balanceB_post = tokenBalanceOf(tokenB, e.msg.sender);

    satisfy tokenA != tokenB && balanceA_pre != balanceA_post && balanceB_pre != balanceB_post;
}

/// @title After a call to 'unlock()', the currency delta of any address must be zero.
/// @notice The default callback is arbitrary that havocs the state. The rule should still be correct
/// for every custom unlockFallback that is used.
rule unlockMustTerminateWithZeroDelta(address caller, PoolManager.Currency currency) {
    requireLockingInvariants();
    env e;
    bytes data;
    unlock(e, data);
    /// strong invariants - can be required after any function call.
    requireLockingInvariants();

    assert PoolGetters.currencyDelta(caller, currency) == 0;
}

/// @title Any call to modifyLiquidity() changes only the correct position in the correct pool liquidity.
rule modifyLiquidityDoesntAffectOthers(PoolManager.PoolId poolId, bytes32 positionId) {
    IPoolManager.ModifyLiquidityParams params;
    
    int24 tick_pre = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(params.liquidityDelta, params.tickLower, params.tickUpper, tick_pre, sqrtPrice_pre);
    uint128 liquidity_pre = getPositionLiquidityExt(poolId, positionId);

    env e;
    PoolManager.PoolKey key;
    PoolManager.PoolId poolIdA = PoolGetters.toId(key);
    IPoolManager.ModifyLiquidityParams paramsA;
    bytes hookData;
    bytes32 positionIdA = PoolGetters.getPositionKey(e.msg.sender, paramsA.tickLower, paramsA.tickUpper, paramsA.salt);
    modifyLiquidity(e, key, paramsA, hookData);
    
    int24 tick_post = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(params.liquidityDelta, params.tickLower, params.tickUpper, tick_post, sqrtPrice_post);
    uint128 liquidity_post = getPositionLiquidityExt(poolId, positionId);

    /// Calculated funds for the same liquidity are the same:
    assert amount0_pre == amount0_post && amount1_pre == amount1_post;
    /// If modified liquidity for another position, no change:
    assert !(positionIdA == positionId && poolId == poolIdA) => liquidity_pre == liquidity_post;
    assert (positionIdA == positionId && poolId == poolIdA) => liquidity_post - liquidity_pre == to_mathint(paramsA.liquidityDelta);
    assert (positionIdA == positionId && poolId == poolIdA) => liquidity_pre + paramsA.liquidityDelta >= 0;
}

/// @title The call to initialize() sets the price of the pool correctly. 
rule initializationSetsPriceCorrectly(PoolManager.PoolKey key, address user) {
    env e;
    uint160 sqrtPriceX96; 
    PoolManager.PoolId poolId = PoolGetters.toId(key);

    int256 user_delta_currency0_pre = PoolGetters.currencyDelta(user, key.currency0);
    int256 user_delta_currency1_pre = PoolGetters.currencyDelta(user, key.currency1);

    bool isInitialized_pre = isPoolInitialized(poolId);
        initialize(e, key, sqrtPriceX96);
    bool isInitialized_post = isPoolInitialized(poolId);

    int256 user_delta_currency0_post = PoolGetters.currencyDelta(user, key.currency0);
    int256 user_delta_currency1_post = PoolGetters.currencyDelta(user, key.currency1);

    assert !isInitialized_pre && isInitialized_post;
    assert PoolGetters.getSqrtPriceX96(poolId) == sqrtPriceX96;
    assert isValidSqrt(sqrtPriceX96);
    assert key.tickSpacing > 0;
    assert user_delta_currency0_pre == user_delta_currency0_post && user_delta_currency1_pre == user_delta_currency1_post;
}

function isPoolInitialized(PoolManager.PoolId poolId) returns bool {
    return PoolGetters.getSqrtPriceX96(poolId) > 0;
}

function TickSqrtPriceCorrespondence(int24 tick, uint160 sqrtPrice) returns bool {
    return
    (sqrtPriceAtTick(tick) <= sqrtPrice && sqrtPrice < sqrtPriceAtTick(require_int24(tick + 1)))
    ||
    (
        (tick < MAX_TICK() => sqrtPriceAtTick(require_int24(tick + 1)) == sqrtPrice) 
        &&
        (tick == MAX_TICK() => sqrtPrice == MAX_SQRT_PRICE())
    );
}

function TickSqrtPriceStrongCorrespondence(int24 tick, uint160 sqrtPrice) returns bool {
    return
    (sqrtPriceAtTick(tick) <= sqrtPrice && sqrtPrice < sqrtPriceAtTick(require_int24(tick + 1)))
    &&
    (tickAtSqrtPrice(sqrtPrice) == tick);
}

definition liquidityGrossBound(PoolManager.PoolId poolId, int24 tick) returns bool = PoolManager._pools[poolId].ticks[tick].liquidityGross <= (1 << 126);

/// @title The gross liquidity of every pool in any tick is bounded by 2^126.
invariant LiquidityGrossBound(PoolManager.PoolKey key, int24 tick) 
    liquidityGrossBound(PoolGetters.toId(key), tick)
    {
        preserved with (env e) {
            requireInvariant InitializedPoolHasValidTickSpacing(key);
        }
    }

/// @title All initialized pools have valid tick spacing.
invariant InitializedPoolHasValidTickSpacing(PoolManager.PoolKey key)
    isPoolInitialized(PoolGetters.toId(key)) => (key.tickSpacing > 0 && key.tickSpacing <= max_uint16);

/// @title For every initialized pool, the tick and sqrt price are valid (bounded by min and max).
invariant ValidTickAndPrice(PoolManager.PoolId poolId)
    isPoolInitialized(poolId) =>
        isValidTick(PoolGetters.getTick(poolId))
        &&
        isValidSqrt(PoolGetters.getSqrtPriceX96(poolId))
        {
            preserved swap(PoolManager.PoolKey key, IPoolManager.SwapParams params, bytes hooks) with (env e) 
            {
                require bitmapPoolId == PoolGetters.toId(key);
            }
        }

/// @title Strong sqrt price-tick correlation in a pool
/// Violated (Certora M-02)
invariant TickSqrtPriceStrongCorrelation(PoolManager.PoolId poolId)
    isPoolInitialized(poolId) => TickSqrtPriceStrongCorrespondence(PoolGetters.getTick(poolId),PoolGetters.getSqrtPriceX96(poolId))    
    {
        preserved swap(PoolManager.PoolKey key, IPoolManager.SwapParams params, bytes hooks) with (env e) 
        {
            requireInvariant ValidTickAndPrice(bitmapPoolId);
            requireInvariant ValidTickAndPrice(poolId);
            require bitmapPoolId == PoolGetters.toId(key);
        }
    }

/// @title Weak sqrt price-tick correlation in a pool
invariant TickSqrtPriceCorrelation(PoolManager.PoolId poolId)
    isPoolInitialized(poolId) => 
        TickSqrtPriceCorrespondence(PoolGetters.getTick(poolId), PoolGetters.getSqrtPriceX96(poolId))
    {
        preserved swap(PoolManager.PoolKey key, IPoolManager.SwapParams params, bytes hooks) with (env e) 
        {
            requireInvariant ValidTickAndPrice(bitmapPoolId);
            requireInvariant ValidTickAndPrice(poolId);
            require bitmapPoolId == PoolGetters.toId(key);
        }
    }

/// @title there is no gross (or net) liquidity for uninitialized ticks.
strong invariant NoGrossLiquidityForUninitializedTick(PoolManager.PoolId poolId)
    forall int24 tick. 
        (isTickInitialized[poolId][tick] <=> liquidityGross(poolId, tick) > 0) 
        &&
        (liquidityGross(poolId, tick) == 0 => liquidityNet(poolId, tick) == 0)
    {
        preserved modifyLiquidity(
            PoolManager.PoolKey key,
            IPoolManager.ModifyLiquidityParams params,
            bytes data
        ) with (env e) {
            require isPoolInitialized(PoolGetters.toId(key)) => key.tickSpacing > 0;
            require bitmapPoolId == PoolGetters.toId(key);
            matchPositionKeyToTicks(params, e.msg.sender);
            requireInvariant NoGrossLiquidityForUninitializedTick(bitmapPoolId);
            requireInvariant liquidityGrossNetInvariant(poolId);
        }
    }

/// @title For every pool, the only non-empty positions are tick-spacing aligned ticks.
strong invariant OnlyAlignedTicksPositions(PoolManager.PoolKey key, PoolGetters.PoolId poolId)
    PoolGetters.toId(key) == poolId => (
    forall int24 tick. (key.tickSpacing > 0 && tick % key.tickSpacing !=0) => 
        (total_liquidity_upper[poolId][tick] == 0 && total_liquidity_lower[poolId][tick] == 0))
    /// Prover issue: strong invariant is trivially violated with complex invariant arguments.
    filtered{f -> !isUnlock(f)}
    {
        preserved {
            require bitmapPoolId == PoolGetters.toId(key);
            requireInvariant InitializedPoolHasValidTickSpacing(key);
            requireInvariant NoGrossLiquidityForUninitializedTick(bitmapPoolId);
            requireInvariant liquidityGrossNetInvariant(bitmapPoolId);
        }
        preserved modifyLiquidity(
            PoolManager.PoolKey keyA,
            IPoolManager.ModifyLiquidityParams params,
            bytes data
        ) with (env e) {
            require bitmapPoolId == PoolGetters.toId(key);
            requireInvariant InitializedPoolHasValidTickSpacing(key);
            requireInvariant NoGrossLiquidityForUninitializedTick(bitmapPoolId);
            requireInvariant liquidityGrossNetInvariant(bitmapPoolId);
            matchPositionKeyToTicks(params, e.msg.sender);
        }
    }

/// @title The pool's sqrt price and tick move in the correct direction (up/down) with respect to zeroForOne (false/true).
rule swapIntegrity(PoolManager.Currency currency0, PoolManager.Currency currency1) {
    requireLockingInvariants();
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params; 
    bytes hooks;
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
    bool isExactIn = amountSpecified < 0;

    PoolManager.PoolId id = PoolGetters.toId(key);
    requireInvariant ValidTickAndPrice(id);
    requireInvariant TickSqrtPriceCorrelation(id);

    // setup swap variables
    require key.currency0 == currency0;
    require key.currency1 == currency1;
    require zeroForOne == params.zeroForOne;
    require amountSpecified == params.amountSpecified;
    require sqrtPriceLimitX96 == params.sqrtPriceLimitX96;

    PoolManager.Currency specifiedCurrency = (isExactIn == zeroForOne) ? currency0 : currency1;
    PoolManager.Currency otherCurrency = (isExactIn != zeroForOne) ? currency0 : currency1;

    address specifiedToken = CurrencyGetters.fromCurrency(specifiedCurrency);
    address otherToken = CurrencyGetters.fromCurrency(otherCurrency);

    uint128 reserves_specified_pre = require_uint128(tokenBalanceOf(specifiedToken, PoolManager));
    uint128 reserves_other_pre = require_uint128(tokenBalanceOf(otherToken, PoolManager));

    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(id);
    int24 tick_pre = PoolGetters.getTick(id);
    uint256 fees_accrued_pre = protocolFeesAccrued(specifiedCurrency);

    mathint delta0Before = PoolGetters.currencyDelta(e.msg.sender, currency0);
    mathint delta1Before = PoolGetters.currencyDelta(e.msg.sender, currency1);

    // execute the swap:
    PoolManager.BalanceDelta swapDelta = swap(e, key, params, hooks);

    uint256 fees_accrued_post = protocolFeesAccrued(specifiedCurrency);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(id);
    int24 tick_post = PoolGetters.getTick(id);

    uint128 reserves_specified_post = require_uint128(tokenBalanceOf(specifiedToken, PoolManager));
    uint128 reserves_other_post = require_uint128(tokenBalanceOf(otherToken, PoolManager));

    int128 deltaSpecified = (zeroForOne == isExactIn) ? CurrencyGetters.amount0(swapDelta) : CurrencyGetters.amount1(swapDelta);

    mathint delta0After = PoolGetters.currencyDelta(e.msg.sender, currency0);
    mathint delta1After = PoolGetters.currencyDelta(e.msg.sender, currency1);

    mathint delta0 = CurrencyGetters.amount0(swapDelta);
    mathint delta1 = CurrencyGetters.amount1(swapDelta);

    // swap until specified amount is swapped or limit price is reached.
    assert to_mathint(deltaSpecified) == to_mathint(amountSpecified) || sqrtPrice_post == sqrtPriceLimitX96;

    // Update Price and Tick Data:
    assert params.zeroForOne => sqrtPrice_pre >= sqrtPrice_post && tick_pre >= tick_post;
    assert !params.zeroForOne => sqrtPrice_pre <= sqrtPrice_post && tick_pre <= tick_post;
}

/// @title Any call to swap() cannot increase the balance deltas of two arbitraty tokens, for the total of hooks and the user.
rule swapCantIncreaseBothCurrencies(PoolManager.Currency tokenA, PoolManager.Currency tokenB) {
    env e;
    PoolManager.PoolKey key;
    /// The PoolManager cannot call itself.
    require e.msg.sender != PoolManager;
    /// The PoolManager doesn't serve as a hook.
    require key.hooks != PoolManager;

    require tokenA != tokenB;
    mathint balance1A_pre = PoolGetters.currencyDelta(e.msg.sender, tokenA); 
    mathint balance1B_pre = PoolGetters.currencyDelta(e.msg.sender, tokenB);
    mathint balance2A_pre = PoolGetters.currencyDelta(key.hooks, tokenA); 
    mathint balance2B_pre = PoolGetters.currencyDelta(key.hooks, tokenB);
        IPoolManager.SwapParams params; 
        bytes hooks;
        swap(e, key, params, hooks);
    mathint balance1A_post = PoolGetters.currencyDelta(e.msg.sender, tokenA); 
    mathint balance1B_post = PoolGetters.currencyDelta(e.msg.sender, tokenB);
    mathint balance2A_post = PoolGetters.currencyDelta(key.hooks, tokenA); 
    mathint balance2B_post = PoolGetters.currencyDelta(key.hooks, tokenB);

    assert balance1A_pre + balance2A_pre < balance1A_post + balance2A_post =>
        balance2B_post + balance1B_post <= balance1B_pre + balance2B_pre;

    assert balance2B_post + balance1B_post != balance1B_pre + balance2B_pre =>
        (tokenB == key.currency0 || tokenB == key.currency1);
}

/// @title Donation cannot decrease LP fees.
rule donationDoesntDecreasePositionValue() {
    requireLockingInvariants();
    env modifyLiquidity_env;
    env donate_env;
    calldataarg donate_args;
    PoolManager.PoolKey key;
    IPoolManager.ModifyLiquidityParams params;
    bytes hookData;

    PoolManager.BalanceDelta callerDelta_first; 
    PoolManager.BalanceDelta feesAccrued_first;
    PoolManager.BalanceDelta callerDelta_second; 
    PoolManager.BalanceDelta feesAccrued_second;

    /// Under-approximation: we assume the hook-free case only.
    require !CVLHasPermission(key.hooks, BEFORE_ADD_LIQUIDITY_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_ADD_LIQUIDITY_FLAG());
    require !CVLHasPermission(key.hooks, BEFORE_REMOVE_LIQUIDITY_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_REMOVE_LIQUIDITY_FLAG());

    // modifyLquidity with a negative liquidy delta (withdrawing)
    require params.liquidityDelta < 0;

    // save initial storage
	storage initStorage = lastStorage;

    // detrmine position value:
    (callerDelta_first, feesAccrued_first) = modifyLiquidity(modifyLiquidity_env, key, params, hookData);

    require feesAccrued_first > 0;

    // save the feesAccrued

    // check results in balance change - fees accrued

    // revert to init state

    //donate or swap (function that changes the fees accrued) at init storage.
    donate(donate_env, donate_args) at initStorage;

    // call modifyLiquidity with the same params
    (callerDelta_second, feesAccrued_second) = modifyLiquidity(modifyLiquidity_env, key, params, hookData);

    // save the feesAccrued

    // assert the the fees accrued doesnt decrease in the second call
    assert feesAccrued_first <= feesAccrued_second;
}

/// @title Liquidity positions cannot be affected by tick-sqrt price misaligment (Certora M-02)
rule liquidityPositionAgnosticM02(PoolManager.PoolKey key)
{
    /// Require pool invariants
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant liquidityGrossNetInvariant(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);

    /// Position parameters
    int24 tickLower;
    int24 tickUpper;
    int128 liquidity;
    /// Enforced for any liquidity position
    require tickUpper <= MAX_TICK();
    require tickLower >= MIN_TICK();
    require tickLower <= tickUpper;

    /// Pre-state
    int24 tick_pre = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_pre; mathint amount1_pre;
    amount0_pre, amount1_pre = getPositionFunds(liquidity, tickLower, tickUpper, tick_pre, sqrtPrice_pre);

    /// Tick misalignment
    require tick_pre + 1 == tickAtSqrtPrice(sqrtPrice_pre);
    /// Position upper tick is lower than corresponding price tick
    require tickUpper <= tickAtSqrtPrice(sqrtPrice_pre);
        env e;
        IPoolManager.SwapParams swapParams;
        require swapParams.zeroForOne == false;
        bytes hookData;
        swap(e, key, swapParams, hookData); 
    /// Post-state
    int24 tick_post = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);
    mathint amount0_post; mathint amount1_post;
    amount0_post, amount1_post = getPositionFunds(liquidity, tickLower, tickUpper, tick_post, sqrtPrice_post);

    assert amount0_post == amount0_pre, "LP cannot receive currency0 tokens from upwards-swap";
    assert amount1_post >= amount1_pre, "LP currency1 position value cannot decrease from upwards-swap";
}
/// @title M-02 behavior only occurs for zeroForOne trades (moving tick towards negative infinity)
/// and only occurs when sqrtPriceLimit is equal to getSqrtPriceAtTick(<tick>)
rule tickMisalignmentOccursOnlyForDownSwaps(PoolManager.PoolKey key) 
{
    /// Require pool invariants
    PoolManager.PoolId poolId = PoolGetters.toId(key);
    require bitmapPoolId == poolId;
    requireInvariant ValidTickAndPrice(poolId);
    requireInvariant InitializedPoolHasValidTickSpacing(key);
    requireInvariant TickSqrtPriceCorrelation(poolId);
    requireInvariant liquidityGrossNetInvariant(poolId);
    requireInvariant NoGrossLiquidityForUninitializedTick(poolId);
    requireInvariant NoLiquidityAtBounds(poolId); 

    /// Pre-state
    int24 tick_pre = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_pre = PoolGetters.getSqrtPriceX96(poolId);
    /// Assuming tick and price are aligned (M-02 invariant)
    require TickSqrtPriceStrongCorrespondence(tick_pre, sqrtPrice_pre);
    /// Tick misalignment
        env e;
        IPoolManager.SwapParams swapParams;
        bytes hookData;
        PoolManager.BalanceDelta swapDelta = swap(e, key, swapParams, hookData);
        int128 swap0 = CurrencyGetters.amount0(swapDelta);
        int128 swap1 = CurrencyGetters.amount1(swapDelta);
    int24 tick_post = PoolGetters.getTick(poolId);
    uint160 sqrtPrice_post = PoolGetters.getSqrtPriceX96(poolId);

    /// If the alignment is broken
    bool misalignment = !TickSqrtPriceStrongCorrespondence(tick_post, sqrtPrice_post);
    /// The conditions for misalignment:
    assert misalignment =>
        /// The tick is down-offset by 1.
        tick_post + 1 == tickAtSqrtPrice(sqrtPrice_post) &&
        /// Only swaps towards -infinity
        swapParams.zeroForOne == true;//&&
        /// The sqrt price was set to the limit
        //swapParams.sqrtPriceLimitX96 == sqrtPrice_post;
    satisfy misalignment;
}