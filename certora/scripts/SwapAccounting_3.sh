#!/bin/bash
certoraRun certora/confs/PoolManager_swapAccounting.conf \
    --rule swappingDoesntSkipLiquiditesOneForZero \
    --rule swappingDoesntSkipLiquiditesZeroForOne \
    --rule positionsToTheLeftDontChangeValue \
    --rule positionsToTheRightDontChangeValue "$@"
