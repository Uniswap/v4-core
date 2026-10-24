#!/bin/bash

certoraRun certora/confs/PoolManager.conf \
    --rule netLiquidityImmutableInSwap \
    --rule nonZeroCorrect \
    --rule nonZeroCounterStepInvariant \
    --rule nonZeroMonotonousInvariant \
    --rule nonZeroStart \
    --rule isLockedAndDeltaZero \
    --rule poolSqrtPriceNeverTurnsZero \
    --rule swapCantIncreaseBothCurrencies \
    --rule lockSanityCheck "$@"
