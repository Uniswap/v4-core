import "../../Summaries/CurrencyDeltaSummary.spec";

methods {
    function CurrencyDelta.applyDelta(PoolManager.Currency currency, address user, int128 delta) internal returns (int256,int256) => setCurrencyDelta(currency, user, delta);
    function CurrencyDelta.getDelta(PoolManager.Currency currency, address user) internal returns int256 => getCurrencyDelta(currency, user);
    function TransientStateLibrary.currencyDelta(address, address user, PoolManager.Currency currency) internal returns (int256) => getCurrencyDelta(currency, user);
}

/// The maximum number of currencies involved in a currency delta rule (used to prevent unrealistic overflows).
definition MAX_NUMBER_OF_DELTA_CURRENCIES() returns mathint = 5;

// Strong invariants should hold between transactions and when a callback is called.
// For callbacks we allow the callback to change the state of the contract as long as it preserves the strong invariants.

/// @title The non-zero cumultative deltas array starts at zero.
strong invariant nonZeroStart() nonZeroCounterArray[0] == 0
{
    preserved {
        requireInvariant nonZeroCorrect();
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
    }
}
/// @title Correctness of the increments of the non-zero deltas array.
strong invariant nonZeroCounterStepInvariant() nonZeroCounterStep()
{
    preserved {
        requireInvariant nonZeroCorrect();
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
    }
}
/// @title The non-zero deltas counter must be montonous.
strong invariant nonZeroMonotonousInvariant() nonZeroMonotonous()
{
    preserved {
        requireInvariant nonZeroCorrect();
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
    }
}

/*/// @title If all deltas are zero then the total non-zero delta count is zero.
strong invariant zeroDeltasCorrect()
    (forall address user. forall address token. ghostCurrencyDelta[user][token] == 0) =>
    nonZeroCounterArray[2^320] == 0
{
    preserved {
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
        require PoolGetters.getNonzeroDeltaCount() < (1<<256) - MAX_NUMBER_OF_DELTA_CURRENCIES(); // prevent overflow, which cannot realistically happen
    }
    preserved onTransactionBoundary {
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
        requireInvariant isLockedAndDeltaZero();
    }
}*/

/// @title The storage non-zero delta count must be equal to the sum of all non-zero deltas counter.
strong invariant nonZeroCorrect()
    to_mathint(PoolGetters.getNonzeroDeltaCount()) == nonZeroCounterArray[2^320]

{
    preserved {
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
        require PoolGetters.getNonzeroDeltaCount() < (1<<256) - MAX_NUMBER_OF_DELTA_CURRENCIES(); // prevent overflow, which cannot realistically happen
    }
    preserved onTransactionBoundary {
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
        requireInvariant isLockedAndDeltaZero();
    }
}

// weak invariants hold before and after the outermost call to the contract.

/// @title before and after every transaction in the PoolManager, the contract should be locked and all currency deltas should be zeroed-out.
weak invariant isLockedAndDeltaZero()
    !PoolGetters.isUnlocked() && PoolGetters.getNonzeroDeltaCount() == 0
{
    preserved {
        requireInvariant nonZeroCorrect();
        requireInvariant nonZeroCounterStepInvariant();
        requireInvariant nonZeroMonotonousInvariant();
        requireInvariant nonZeroStart();
    }
}

/// @title Verifies that the conjunction of locking invariants isn't vacuous.
rule lockSanityCheck(method f) {
    env e;
    calldataarg args;

    requireInvariant nonZeroCorrect();
    requireInvariant nonZeroCounterStepInvariant();
    requireInvariant nonZeroMonotonousInvariant();
    requireInvariant nonZeroStart();

    f(e, args);
    satisfy true;
}
