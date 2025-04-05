
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PoolIdLibrary, PoolKey, PoolId } from "src/types/PoolId.sol";
import { StateLibrary } from "src/libraries/StateLibrary.sol";
import { Position } from "src/libraries/Position.sol";
import { TransientStateLibrary } from "src/libraries/TransientStateLibrary.sol";
import { Slot0Library, Slot0 } from "src/types/Slot0.sol";
import { IPoolManager } from "src/interfaces/IPoolManager.sol";
import { PoolManager } from "src/PoolManager.sol";
import { Currency } from "src/types/Currency.sol";

contract PoolStateGetters is PoolManager {
    constructor(address initialOwner) PoolManager(initialOwner) {}
    /// Slot0

    function _getSlot0(PoolId poolId) internal view returns (Slot0) {
        return _getPool(poolId).slot0;
    }

    function getSqrtPriceX96(PoolId poolId) public view returns (uint160) {
        return Slot0Library.sqrtPriceX96(_getSlot0(poolId));
    }

    function getTick(PoolId poolId) public view returns (int24) {
        return Slot0Library.tick(_getSlot0(poolId));
    }

    function getProtocolFee(PoolId poolId) public view returns (uint24) {
        return Slot0Library.protocolFee(_getSlot0(poolId));
    }

    function getLpFee(PoolId poolId) public view returns (uint24) {
        return Slot0Library.lpFee(_getSlot0(poolId));
    }

    /// Liquidity

    function getLiquidity(PoolId poolId) public view returns (uint128) {
        return _getPool(poolId).liquidity;
    }

    function getFeeGlobal0x128(PoolId poolId) public view returns (uint256) {
        return _getPool(poolId).feeGrowthGlobal0X128;
    }

    function getFeeGlobal1x128(PoolId poolId) public view returns (uint256) {
        return _getPool(poolId).feeGrowthGlobal1X128;
    }

    /// Tick

    function getTickLiquidityGross(PoolId poolId, int24 tick) public view returns (uint128) {
        return _getPool(poolId).ticks[tick].liquidityGross;
    }

    function getTickLiquidityNet(PoolId poolId, int24 tick) public view returns (int128) {
        return _getPool(poolId).ticks[tick].liquidityNet;
    }

    function getTickfeeGrowth0x128(PoolId poolId, int24 tick) public view returns (uint256) {
        return _getPool(poolId).ticks[tick].feeGrowthOutside0X128;
    }

    function getTickfeeGrowth1x128(PoolId poolId, int24 tick) public view returns (uint256) {
        return _getPool(poolId).ticks[tick].feeGrowthOutside1X128;
    }

    /// Positions

    function getPositionLiquidity(PoolId poolId, bytes32 positionKey) public view returns (uint128) {
        return _getPool(poolId).positions[positionKey].liquidity;
    }

    function getPositionfeeGrowth0x128(PoolId poolId, bytes32 positionKey) public view returns (uint256) {
        return _getPool(poolId).positions[positionKey].feeGrowthInside0LastX128;
    }

    function getPositionfeeGrowth1x128(PoolId poolId, bytes32 positionKey) public view returns (uint256) {
        return _getPool(poolId).positions[positionKey].feeGrowthInside1LastX128;
    }

    /// TickBitmap
    
    function getTickBitmap(PoolId poolId, int16 wordPos) public view returns (uint256) {
        return _getPool(poolId).tickBitmap[wordPos];
    }
}
