// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {V3PoolImplementation} from '../implementations/V3PoolImplementation.sol';

contract MockTimeV3PoolImplementation is V3PoolImplementation {
    constructor(
        IPoolManager _manager,
        uint24 _fee,
        int24 _tickSpacing
    ) V3PoolImplementation(_manager, _fee, _tickSpacing) {}

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
