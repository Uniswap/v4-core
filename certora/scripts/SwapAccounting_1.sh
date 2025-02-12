#!/bin/bash
certoraRun certora/confs/PoolManager_swapAccounting.conf \
    --rule swapDeltasCoveredByAmountsDeltaOfActiveLiquidityOneForZero \
    --rule swapDeltasCoveredByAmountsDeltaOfActiveLiquidityZeroForOne "$@"
certoraRun certora/confs/PoolManager_swapAccounting.conf --rule swapIntegrity "$@"
