// The nonZeroCounterArray counts the nonzero entries in currencyDelta.
// It starts at 0 and increments by one for every nonzero entry in currencyDelta.
// nonZeroCounterArray[2^320] should be equal to getNonzeroDeltaCount().
ghost mapping(mathint => mathint) nonZeroCounterArray {
    init_state axiom forall mathint i. nonZeroCounterArray[i] == 0;
}

ghost mapping(address => mapping(address => int256)) ghostCurrencyDelta {
    init_state axiom forall address user. forall address token. ghostCurrencyDelta[user][token] == 0;
}

ghost mapping(address => mathint) ghostCurrencySum {
    init_state axiom forall address token. ghostCurrencySum[token] == 0;
}

// make a single mathint from two adddresses.
definition hashInt(address user, address token) returns mathint = (to_mathint(user) * 2^160 + to_mathint(token));

// The main invariants for the nonZeroCounterArray.
definition nonZeroCounterStep() returns bool =
    forall address user. forall address token.
        nonZeroCounterArray[hashInt(user,token)+1] ==
            nonZeroCounterArray[hashInt(user,token)] + (ghostCurrencyDelta[user][token] != 0 ? 1 : 0);
definition nonZeroMonotonous() returns bool =
    forall mathint i. forall mathint j. i <= j => nonZeroCounterArray[i] <= nonZeroCounterArray[j];

// Hooks for currencyDelta: keep a ghost copy and update the nonZeroCounterArray.
// We prove that the update is correct and satisfies the nonZeroCounterArray invariants.
function getCurrencyDelta(PoolManager.Currency currency, address user) returns int256 {
    return ghostCurrencyDelta[user][CurrencyGetters.fromCurrency(currency)];
}
function setCurrencyDelta(PoolManager.Currency currency, address user, int128 delta) returns (int256,int256) {
    address token = CurrencyGetters.fromCurrency(currency);
    int256 oldv = ghostCurrencyDelta[user][token];
    int256 v = require_int256(oldv + delta);
    mathint userTokenHash = hashInt(user, token);
    mathint delta0;
    if (oldv != 0 && v == 0) {
        delta0 = -1;
    } else if (oldv == 0 && v != 0) {
        delta0 = 1;
    } else {
        delta0 = 0;
    }
    havoc nonZeroCounterArray assuming
        forall mathint i. nonZeroCounterArray@new[i] ==
            nonZeroCounterArray@old[i] + (i > to_mathint(userTokenHash) ? delta0 : 0);
    ghostCurrencyDelta[user][token] = v;
    ghostCurrencySum[token] = ghostCurrencySum[token] + delta;
    return (oldv, v);
}