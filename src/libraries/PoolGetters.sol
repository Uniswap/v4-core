// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Pool} from "./Pool.sol";

library PoolGetters {
    function getPoolTickInfo(Pool.State storage pool, int24 tick) internal view returns (Pool.TickInfo memory) {
        return pool.ticks[tick];
    }

    function getPoolBitmapInfo(Pool.State storage pool, int16 word) internal view returns (uint256 tickBitmap) {
        return pool.tickBitmap[word];
    }
}
