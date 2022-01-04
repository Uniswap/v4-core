// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {PoolManager} from '../PoolManager.sol';

contract MockTimePoolManager is PoolManager {
    uint32 public time;

    function _blockTimestamp() internal view override returns (uint32) {
        return time;
    }

    function advanceTime(uint32 by) external {
        unchecked {
            time += by;
        }
    }
}
