#!/bin/bash
certoraRun certora/confs/PoolManager_swapAccounting.conf \
    --rule activeLiquidityUpdatedCorrectly \
    --rule ValidTickAndPrice \
    --rule TickSqrtPriceCorrelation \
    --rule OnlyAlignedTicksPositions \
    --rule NoLiquidityAtBounds \
    --rule NoGrossLiquidityForUninitializedTick \
    --rule LiquidityGrossBound \
    --rule InitializedPoolHasValidTickSpacing \
    --rule inactivePositionFundsDontChangeAfterSwap "$@"
