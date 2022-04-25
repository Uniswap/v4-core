// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {GeomeanOracle} from '../hooks/GeomeanOracle.sol';

contract MockTimeGeomeanOracle is GeomeanOracle {
    uint32 public time;

    constructor(IPoolManager _poolManager) GeomeanOracle(_poolManager) {
        time = 1;
    }

    function setTime(uint32 _time) external {
        time = _time;
    }

    function _blockTimestamp() internal view override returns (uint32) {
        return time;
    }
}
