#!/bin/bash

certoraRun certora/confs/ProtocolFeeLibrary.conf "$@"
certoraRun certora/confs/SqrtPriceMath.conf "$@"
certoraRun certora/confs/TickBitmapTest.conf \
    --rule sanity "$@"
certoraRun certora/confs/TickBitmapTest.conf \
    --exclude_rule sanity "$@"
certoraRun certora/confs/SwapMathTest.conf "$@"
certoraRun certora/confs/CurrencyDelta.conf "$@"
certoraRun certora/confs/StateLibrary.conf "$@"
