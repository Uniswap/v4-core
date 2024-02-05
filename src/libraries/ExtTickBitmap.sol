// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {UnsignedSignedMath} from "./UnsignedSignedMath.sol";
import {Pool} from "./Pool.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";

import {LibString} from "solmate/utils/LibString.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
library ExtTickBitmap {
    using LibString for int256;

    using ExtTickBitmap for IPoolManager;
    using UnsignedSignedMath for uint128;
    using PoolIdLibrary for PoolKey;
    using TickBitmap for int24;
    using TickBitmap for uint256;

    error StartEndOutOfOrder();

    function getTotalNetLiquidity(IPoolManager manager, PoolKey memory key, int24 startTick, int24 inclusiveEndTick)
        internal
        view
        returns (int128 totalLiquidityNet)
    {
        if (startTick > inclusiveEndTick) revert StartEndOutOfOrder();
        int24 nextIndex = startTick.compress(key.tickSpacing);
        int24 inclusiveEndIndex = inclusiveEndTick.compress(key.tickSpacing);
        PoolId id = key.toId();
        bool initialized = false;

        while (true) {
            (nextIndex, initialized) = manager.nextInitializedIndexWithinOneWord(id, nextIndex, false);
            if (nextIndex > inclusiveEndIndex) break;
            if (initialized) {
                int24 tick = nextIndex * key.tickSpacing;
                Pool.TickInfo memory tickInfo = manager.getPoolTickInfo(id, tick);
                totalLiquidityNet += tickInfo.liquidityNet;
            }
        }
    }

    function indexInitialized(IPoolManager manager, PoolId id, int24 index) internal view returns (bool) {
        (int16 wordPos, uint8 bitPos) = index.position();
        uint256 bitmapWord = manager.getPoolBitmapInfo(id, wordPos);
        return bitmapWord & (1 << bitPos) != 0;
    }

    function nextInitializedIndexWithinOneWord(IPoolManager manager, PoolId id, int24 index, bool lte)
        internal
        view
        returns (int24 nextIndex, bool initialized)
    {
        int16 wordPos;
        uint8 bitPos;
        uint8 nextBitPos;
        if (lte) {
            (wordPos, bitPos) = index.position();
            (nextBitPos, initialized) = manager.getPoolBitmapInfo(id, wordPos).nextBitPosLte(bitPos);
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            (wordPos, bitPos) = (index + 1).position();
            (nextBitPos, initialized) = manager.getPoolBitmapInfo(id, wordPos).nextBitPosGt(bitPos);
        }
        // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
        nextIndex = (int24(wordPos) << 8) + int24(uint24(nextBitPos));
    }
}
