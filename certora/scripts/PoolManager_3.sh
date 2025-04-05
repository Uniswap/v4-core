#!/bin/bash

certoraRun certora/confs/PoolManager.conf \
    --rule donationDoesntDecreasePositionValue "$@"
