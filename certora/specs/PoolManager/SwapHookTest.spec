import "../Summaries/SqrtPriceMathDetSummary.spec";
import "../Summaries/TickMathSummary.spec";
import "../Summaries/UnsafeMathSummary.spec";
import "../Summaries/FullMathSummary.spec";
import "../Summaries/PoolStateTickBitmapMirror.spec";
import "../Summaries/CVLERC20.spec";
import "./setup/IUnlockCallback.spec";
import "../Summaries/ProtocolFeeLibrary.spec";
import "./setup/extsload.spec";
import "./setup/lock.spec";
import "../Summaries/SwapStepSummary.spec";

using PoolManager as PoolManager;
using PoolGetters as PoolGetters;
using PoolSwapTest as SwapRouter;
using DeltaReturningHook as DeltaReturningHook;

methods {
    function PoolGetters.isUnlocked() external returns (bool) envfree;
    function PoolGetters.toId(PoolManager.PoolKey) external returns (PoolManager.PoolId) envfree;
    function PoolGetters.getNonzeroDeltaCount() external returns (uint256) envfree;
    function PoolGetters.currencyDelta(address,PoolManager.Currency) external returns (int256) envfree;
    function PoolGetters.getPositionKey(address,int24,int24,bytes32) external returns (bytes32) envfree;
    function CurrencyGetters.amount0(PoolManager.BalanceDelta) external returns (int128) envfree;
    function CurrencyGetters.amount1(PoolManager.BalanceDelta) external returns (int128) envfree;
}

definition SqrtPriceLimitX96(bool zeroForOne) returns mathint =
    zeroForOne ? MIN_SQRT_PRICE() - 1 : MAX_SQRT_PRICE() + 1;

/// Formal version of the test customAccounting.t.sol / test_fuzz_swap_beforeSwap_returnsDeltaSpecified
rule test_FV_swap_beforeSwap_returnsDeltaSpecified(
   PoolManager.Currency currency0,
   PoolManager.Currency currency1,
   int128 hookDeltaSpecified,
   int256 amountSpecified,
   bool zeroForOne
) {
    env e;  /// Context environment for call to swap()
    PoolManager.PoolKey key;
    IPoolManager.SwapParams params;
    PoolSwapTest.TestSettings testSettings;
    bytes hooksData; require hooksData.length == 0; /// == ZERO_BYTES

    /// Assume reasonable currency delta:
    require forall address user. forall address token.
        ghostCurrencyDelta[user][token] <= (1 << 120) &&
        ghostCurrencyDelta[user][token] >= -(1 << 120);

    /// Actor isn't a contract:
    require e.msg.sender != PoolManager;
    require e.msg.sender != SwapRouter;
    require e.msg.sender != DeltaReturningHook;

    // setup swap variables
    require key.currency0 == currency0;
    require key.currency1 == currency1;
    require key.fee == 100;
    require key.hooks == DeltaReturningHook;

    /// Set permissions for hook:
    require CVLHasPermission(key.hooks, BEFORE_SWAP_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_SWAP_FLAG());
    require CVLHasPermission(key.hooks, BEFORE_SWAP_RETURNS_DELTA_FLAG());
    require !CVLHasPermission(key.hooks, AFTER_SWAP_RETURNS_DELTA_FLAG());

    require testSettings.takeClaims == false;
    require testSettings.settleUsingBurn == false;

    require params.zeroForOne == zeroForOne;
    require params.amountSpecified == amountSpecified;
    require params.sqrtPriceLimitX96 == assert_uint160(SqrtPriceLimitX96(zeroForOne));

    bool isExactIn = amountSpecified < 0;
    PoolManager.Currency specifiedCurrency = (isExactIn == zeroForOne) ? currency0 : currency1;
    /// Convert from "Currency" to "address" (= unwrap)
    address specifiedToken = CurrencyGetters.fromCurrency(specifiedCurrency);

    /// Maximum extractable liquidity
    /// @dev Should think if there is need to correlate those with reserves or not.
    int128 maxPossibleIn; /// <0
    int128 maxPossibleOut; /// >0
    if (isExactIn) {
        require maxPossibleIn < 0;
    } else {
        require maxPossibleOut > 0;
    }

    // bound delta in specified to not take more than the reserves available, nor be the minimum int to
    // stop the hook reverting on take/settle
    uint128 reservesOfSpecified = require_uint128(tokenBalanceOf(specifiedToken, PoolManager));
    env e1;
    require hookDeltaSpecified > MIN_INT128() && to_mathint(hookDeltaSpecified) <= to_mathint(reservesOfSpecified);

    /// Since storage state is arbitrary, it's equivalent to 'require DeltaReturningHook.deltaSpecified == hookDeltaSpecified;'
    DeltaReturningHook.setDeltaSpecified(e1, hookDeltaSpecified);
    /// Assume no ETH was sent to the Router before.
    //require tokenBalanceOf(0, SwapRouter) == 0;

    /// Query balances() - pre
    uint256 balanceSenderBefore = tokenBalanceOf(specifiedToken, e.msg.sender);
    uint256 balanceHookBefore = tokenBalanceOf(specifiedToken, DeltaReturningHook);
    uint256 balanceManagerBefore = tokenBalanceOf(specifiedToken, PoolManager);

    /// Execute swap()
    PoolManager.BalanceDelta delta = SwapRouter.swap(e, key, params, testSettings, hooksData);
    int128 deltaSpecified = (zeroForOne == isExactIn) ? CurrencyGetters.amount0(delta) : CurrencyGetters.amount1(delta);

    /// Query balances() - post
    uint256 balanceSenderAfter = tokenBalanceOf(specifiedToken, e.msg.sender);
    uint256 balanceHookAfter = tokenBalanceOf(specifiedToken, DeltaReturningHook);
    uint256 balanceManagerAfter = tokenBalanceOf(specifiedToken, PoolManager);

    /// swap() didn't revert, then the following must hold:
    assert !(amountSpecified ==0);
    assert !(isExactIn && hookDeltaSpecified + amountSpecified > 0);
    assert !(!isExactIn && amountSpecified + hookDeltaSpecified < 0);

    // in all cases the hook gets what they took, and the user gets the swap's output delta (checked more below)
    assert (
        balanceHookBefore + hookDeltaSpecified == to_mathint(balanceHookAfter),
        "hook balance change incorrect"
    );
    assert (
        balanceSenderBefore + deltaSpecified == to_mathint(balanceSenderAfter),
        "swapper balance change incorrect"
    );

    // exact input, where there arent enough input reserves available to pay swap and hook
    // note: all 3 values are negative, so we use <
    if (isExactIn && (hookDeltaSpecified + amountSpecified < to_mathint(maxPossibleIn))) {
        // the hook will have taken hookDeltaSpecified of the maxPossibleIn
        assert (
            to_mathint(deltaSpecified) == maxPossibleIn - hookDeltaSpecified,
            "deltaSpecified exact input"
        );
        // the manager received all possible input tokens
        assert (
            balanceManagerBefore - maxPossibleIn == to_mathint(balanceManagerAfter),
            "manager balance change exact input"
        );

        // exact output, where there isnt enough output reserves available to pay swap and hook
    } else if (!isExactIn && (hookDeltaSpecified + amountSpecified > to_mathint(maxPossibleOut))) {
        // the hook will have taken hookDeltaSpecified of the maxPossibleOut
        assert (
            to_mathint(deltaSpecified) == maxPossibleOut - hookDeltaSpecified,
            "deltaSpecified exact output"
        );
        // the manager sent out all possible output tokens
        assert (
            balanceManagerBefore - maxPossibleOut == to_mathint(balanceManagerAfter),
            "manager balance change exact output"
        );

        // enough reserves were available, so the user got what they desired
    } else {
        assert (
            to_mathint(deltaSpecified) == to_mathint(amountSpecified),
            "deltaSpecified not amountSpecified"
        );
        assert(
            balanceManagerBefore - amountSpecified - hookDeltaSpecified == to_mathint(balanceManagerAfter),
            "manager balance change not"
        );
    }
}
