#!/bin/bash

certoraRun certora/confs/PoolManager.conf \
    --rule swapPriceChangeWitness \
    --rule swapTokensCurrencyDeltaChangeWitness \
    --rule unlockTokensBalanceChangeWitness \
    --rule modifyLiquidityDoesntAffectOthers \
    --rule liquidityChangedByOwnerOnly \
    --rule initializationSetsPriceCorrectly \
    --rule canBeCalledIfLocked \
    --rule modifyLiquidityDoesntAffectOthers \
    --rule ValidSwapFee "$@"
