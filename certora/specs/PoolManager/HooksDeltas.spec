import "../Summaries/TickMathSummary.spec";
import "../Summaries/UnsafeMathSummary.spec";
import "../Summaries/FullMathSummary.spec";
import "../Common/CVLMath.spec";
import "./setup/HooksNONDET.spec";
import "../Summaries/PoolStateTickBitmapMirror.spec";
import "../Summaries/CVLERC20.spec";
import "../Summaries/ProtocolFeeLibrary.spec";
import "./setup/extsload.spec";
import "./setup/lock.spec";
import "../Common/TickMathDefinitions.spec";
import "../Summaries/SqrtPriceMathDetSummary.spec";
import "../Summaries/SwapStepDetSummary.spec";

using PoolManager as PoolManager;
using PoolGetters as PoolGetters;
using HooksTest as HooksTest;

methods {
    function PoolGetters.getNonzeroDeltaCount() external returns (uint256) envfree;
    function PoolGetters.currencyDelta(address,PoolManager.Currency) external returns (int256) envfree;
    function PoolGetters.isUnlocked() external returns (bool) envfree;
    function PoolGetters.toId(PoolManager.PoolKey) external returns (PoolManager.PoolId) envfree;
    function ParseBytes.parseSelector(bytes memory) internal returns (bytes4) => NONDET;
   
    /// Replace the calculation with a constant value. This summary is valid as long as a rule interacts with a single pool.
    function Pool.tickSpacingToMaxLiquidityPerTick(int24) internal returns (uint128) => CONSTANT;

    function Hooks.callHook(address self, bytes memory data) internal returns (bytes memory) => randomHook(self, data);
    function Hooks.callHookWithReturnDelta(address self, bytes memory data, bool parseReturn) internal returns (int256) => NONDET;
}

definition isDynamicFee(PoolManager.PoolKey key) returns bool = key.fee == 0x800000;

/// @title A hook with no permission for before-swap operation, cannot change the swap specified amount in the swap parameters.
rule beforeSwapPermissionIntegrity(address _hook) {
    /// Before swap parameters
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params; 
    bytes hookData;

    bool has_beforeSwap_permission = CVLHasPermission(_hook, BEFORE_SWAP_RETURNS_DELTA_FLAG());
    bool _isDynamicFee = isDynamicFee(key);

    /// Output values
    int256 amountToSwap; int256 hookReturn; uint24 lpFeeOverride;
    amountToSwap, hookReturn, lpFeeOverride = HooksTest.beforeSwap(e, _hook, key, params, hookData);

    assert !has_beforeSwap_permission => amountToSwap == params.amountSpecified;
    assert !_isDynamicFee => lpFeeOverride == 0;
    satisfy amountToSwap != params.amountSpecified;
}

/// @title Each of the next three rules below proves that when interacting with a pool, only the msg.sender 
/// and the pool hook address could be granted/subtracted currency delta.

rule onlyHookAndSenderDeltasChangeSwap(address account, PoolManager.Currency currency) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooks;
    address hookAddress = key.hooks;

    int256 delta_pre = PoolGetters.currencyDelta(account, currency);
        swap(e, key, params, hooks);
    int256 delta_post = PoolGetters.currencyDelta(account, currency);

    assert account != hookAddress && account != e.msg.sender => delta_pre == delta_post,
        "During a swap, only the pool hook address or the msg.sender could gain/lose currency deltas";
    assert currency != key.currency0 && currency != key.currency1 => delta_pre == delta_post,
        "Only deltas for pool currencies could change.";
}

rule onlyHookAndSenderDeltasChangeModifyLiquidity(address account, PoolManager.Currency currency) {
    env e;
    PoolManager.PoolKey key;
    IPoolManager.ModifyLiquidityParams params;
    bytes hooks;
    address hookAddress = key.hooks;

    int256 delta_pre = PoolGetters.currencyDelta(account, currency);
        modifyLiquidity(e, key, params, hooks);
    int256 delta_post = PoolGetters.currencyDelta(account, currency);

    assert account != hookAddress && account != e.msg.sender => delta_pre == delta_post,
        "During modification of liquidity, only the pool hook address or the msg.sender could gain/lose currency deltas";
    assert currency != key.currency0 && currency != key.currency1 => delta_pre == delta_post,
        "Only deltas for pool currencies could change.";
}

rule onlyHookAndSenderDeltasChangeDonate(address account, PoolManager.Currency currency) {
    env e;
    PoolManager.PoolKey key;
    uint256 amount0; uint256 amount1;
    bytes hooks;
    address hookAddress = key.hooks;

    int256 delta_pre = PoolGetters.currencyDelta(account, currency);
        donate(e, key, amount0, amount1, hooks);
    int256 delta_post = PoolGetters.currencyDelta(account, currency);

    assert account != hookAddress && account != e.msg.sender => delta_pre == delta_post,
        "During a donate, only the pool hook address or the msg.sender could gain/lose currency deltas";
    assert currency != key.currency0 && currency != key.currency1 => delta_pre == delta_post,
        "Only deltas for pool currencies could change.";
}

/// @title Each of the next three rules below proves that no matter what value of delta the hook address returns,
/// the sum of currency deltas for the msg.sender and the hook address is invariant.
rule swapHookSenderDeltasSumIsPreserved() {
    env e1;
    env e2;
    require e1.msg.sender == e2.msg.sender;

    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    bytes hooksA;
    bytes hooksB;
    address hookAddress = key.hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);

    storage initState = lastStorage;

    /// By relying on the correctness of the rule 'beforeSwapPermissionIntegrity',
    /// we make sure that the swapped amount stays the same.
    require !CVLHasPermission(key.hooks, BEFORE_SWAP_RETURNS_DELTA_FLAG());
    require !isDynamicFee(key);
    
    int24 nextTickA = nextTickGhost;
    swap(e1, key, params, hooksA) at initState;

    int256 deltaSender0_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_A = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_A = PoolGetters.currencyDelta(hookAddress, key.currency1);

    int24 nextTickB = nextTickGhost;
    swap(e2, key, params, hooksB) at initState;

    int256 deltaSender0_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_B = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_B = PoolGetters.currencyDelta(hookAddress, key.currency1);

    /// We must (and may) require that the two swaps yielded the same next tick, as it's determined solely by
    /// the pool tick bitmap (which is identical between both calls).
    require nextTickA == nextTickB;

    assert 
    deltaSender0_B + deltaHook0_B == deltaSender0_A + deltaHook0_A
    &&
    deltaSender1_B + deltaHook1_B == deltaSender1_A + deltaHook1_A;
    //satisfy deltaHook0_B != deltaHook0_A;
}

/// TIME-OUT
rule modifyLiquidityHookSenderDeltasSumIsPreserved() {
    env e1;
    env e2;
    require e1.msg.sender == e2.msg.sender;

    PoolManager.PoolKey key;
    IPoolManager.ModifyLiquidityParams params;
    bytes hooksA;
    bytes hooksB;
    address hookAddress = key.hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);

    storage initState = lastStorage;

    modifyLiquidity(e1, key, params, hooksA) at initState;

    int256 deltaSender0_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_A = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_A = PoolGetters.currencyDelta(hookAddress, key.currency1);

    modifyLiquidity(e2, key, params, hooksB) at initState;

    int256 deltaSender0_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_B = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_B = PoolGetters.currencyDelta(hookAddress, key.currency1);

    assert 
    deltaSender0_B + deltaHook0_B == deltaSender0_A + deltaHook0_A
    &&
    deltaSender1_B + deltaHook1_B == deltaSender1_A + deltaHook1_A;
    //satisfy deltaHook0_B != deltaHook0_A;
}

rule donateHookSenderDeltasSumIsPreserved() {
    env e1;
    env e2;
    require e1.msg.sender == e2.msg.sender;

    PoolManager.PoolKey key;
    uint256 amount0; uint256 amount1;
    bytes hooksA;
    bytes hooksB;
    address hookAddress = key.hooks;
    PoolManager.PoolId poolId = PoolGetters.toId(key);

    storage initState = lastStorage;

    donate(e1, key, amount0, amount1, hooksA) at initState;

    int256 deltaSender0_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_A = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_A = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_A = PoolGetters.currencyDelta(hookAddress, key.currency1);

    donate(e2, key, amount0, amount1, hooksB) at initState;

    int256 deltaSender0_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency0);
    int256 deltaSender1_B = PoolGetters.currencyDelta(e1.msg.sender, key.currency1);
    int256 deltaHook0_B = PoolGetters.currencyDelta(hookAddress, key.currency0);
    int256 deltaHook1_B = PoolGetters.currencyDelta(hookAddress, key.currency1);

    assert deltaSender0_B + deltaHook0_B == deltaSender0_A + deltaHook0_A;
    assert deltaSender1_B + deltaHook1_B == deltaSender1_A + deltaHook1_A;
}
