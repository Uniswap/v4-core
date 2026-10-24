import "../Summaries/CurrencyDeltaSummary.spec";

using CurrencyDeltaTest as test;
using CurrencyGetters as CurrencyGetters;

methods {
    function test.getDelta(CurrencyDeltaTest.Currency currency, address target) external returns (int256) envfree;
    function test.applyDelta(CurrencyDeltaTest.Currency currency, address target, int128 delta) external returns (int256, int256);
    function CurrencyGetters.fromCurrency(CurrencyDeltaTest.Currency) external returns (address) envfree;
}

/// @title Verifies the equivalence between the CurrencyDelta.applyDelta function and its 
/// CVL summary counterpart setCurrencyDelta.
rule currencyDeltaEquivalence(CurrencyDeltaTest.Currency currency, address target) {
    storage initState = lastStorage;

    /// CVL
    int256 deltaCVL_pre = getCurrencyDelta(currency, target);
    /// Transient storage 
    int256 deltaTRS_pre = test.getDelta(currency, target);

        env e;
        CurrencyDeltaTest.Currency _applyCurrency;
        address _applyTarget;
        int128 _applyDelta;

        /// Apply delta in Solidity
        int256 prevSOL; int256 nextSOL;
        prevSOL, nextSOL = test.applyDelta(e, _applyCurrency, _applyTarget, _applyDelta) at initState;
        /// Apply delta through CVL
        int256 prevCVL; int256 nextCVL;
        prevCVL, nextCVL = setCurrencyDelta( _applyCurrency, _applyTarget, _applyDelta);

    /// CVL
    int256 deltaCVL_post = getCurrencyDelta(currency, target);
    /// Transient storage 
    int256 deltaTRS_post = test.getDelta(currency, target);

    /// The CVL state must change in the same manner as the transient storage state.
    assert deltaCVL_pre == deltaTRS_pre => deltaCVL_post == deltaTRS_post;
    /// If the state in (currency, target) was equivalent before, then applying a delta
    /// must return the same value. 
    assert deltaCVL_pre == deltaTRS_pre && _applyTarget == target && _applyCurrency == currency
        => prevSOL == prevCVL && nextSOL == nextCVL;
}