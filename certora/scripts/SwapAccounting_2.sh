#!/bin/bash
certoraRun certora/confs/PoolManager_swapAccounting.conf \
    --rule positionFundsChangeUponTickSlipMaxUpper \
    --rule positionFundsChangeUponTickSlipMinLower \
    --rule positionExtremalTickSeparation \
    --rule integrityOfCrossingTicks "$@"
