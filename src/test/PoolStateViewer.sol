// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "../types/PoolId.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolStateLibrary} from "../libraries/PoolStateLibrary.sol";
import {Currency} from "../types/Currency.sol";

contract PoolStateViewer {
    using PoolStateLibrary for IPoolManager;

    IPoolManager private immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        return poolManager.getSlot0(poolId);
    }

    function getTickInfo(PoolId poolId, int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128
        )
    {
        return poolManager.getTickInfo(poolId, tick);
    }

    function getTickLiquidity(PoolId poolId, int24 tick)
        external
        view
        returns (uint128 liquidityGross, int128 liquidityNet)
    {
        return poolManager.getTickLiquidity(poolId, tick);
    }

    function getTickFeeGrowthOutside(PoolId poolId, int24 tick)
        external
        view
        returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128)
    {
        return poolManager.getTickFeeGrowthOutside(poolId, tick);
    }

    function getFeeGrowthGlobal(PoolId poolId)
        external
        view
        returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1)
    {
        return poolManager.getFeeGrowthGlobal(poolId);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128 liquidity) {
        return poolManager.getLiquidity(poolId);
    }

    function getTickBitmap(PoolId poolId, int16 tick) external view returns (uint256 tickBitmap) {
        return poolManager.getTickBitmap(poolId, tick);
    }

    function getPositionInfo(PoolId poolId, bytes32 positionId)
        external
        view
        returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
    {
        return poolManager.getPositionInfo(poolId, positionId);
    }

    function getPositionLiquidity(PoolId poolId, bytes32 positionId) external view returns (uint128 liquidity) {
        return poolManager.getPositionLiquidity(poolId, positionId);
    }

    function getFeeGrowthInside(PoolId poolId, int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        return poolManager.getFeeGrowthInside(poolId, tickLower, tickUpper);
    }

    function getReserves(Currency currency) external view returns (uint256 value) {
        return poolManager.getReserves(currency);
    }
}
