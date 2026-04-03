#!/bin/bash

certoraRun certora/confs/PoolManager_hooks.conf \
    --exclude_rule modifyLiquidityHookSenderDeltasSumIsPreserved "$@"
