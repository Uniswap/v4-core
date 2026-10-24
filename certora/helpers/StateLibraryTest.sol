// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { PoolId } from "src/types/PoolId.sol";
import { StateLibrary } from "src/libraries/StateLibrary.sol";
import { IPoolManager } from "src/interfaces/IPoolManager.sol";
import { Slot0Library, Slot0 } from "src/types/Slot0.sol";

contract StateLibraryTest {
    using StateLibrary for IPoolManager;
    
    IPoolManager private immutable manager;

    constructor(address _manager) {
        manager = IPoolManager(_manager);
    }

    function getSlot0(PoolId poolId) external view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) 
    {
        return manager.getSlot0(poolId);
    }

    function getTickInfo(PoolId poolId, int24 tick) external view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128
        )
    {
        return manager.getTickInfo(poolId, tick);
    }

    function getTickLiquidity(PoolId poolId, int24 tick) external view
        returns (uint128 liquidityGross, int128 liquidityNet)
    {
        return manager.getTickLiquidity(poolId, tick);
    }

    function getFeeGrowthGlobals(PoolId poolId) external view
        returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1) 
    {
        return manager.getFeeGrowthGlobals(poolId);
    }

    function getTickFeeGrowthOutside(PoolId poolId, int24 tick) external view
        returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128)
    {
        return manager.getTickFeeGrowthOutside(poolId, tick);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128 liquidity) 
    {
        return manager.getLiquidity(poolId);
    }

    function getPositionInfo(PoolId poolId, bytes32 positionId) external view
        returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
    {
        return manager.getPositionInfo(poolId, positionId);
    }

    function getTickBitmap(PoolId poolId, int16 tick) external view returns (uint256 tickBitmap)
    {
        return manager.getTickBitmap(poolId, tick);
    }

    function getPositionLiquidity(PoolId poolId, bytes32 positionId) external view returns (uint128 liquidity)
    {
        return manager.getPositionLiquidity(poolId, positionId);
    }

    function getSqrtPriceX96(Slot0 packed) external view returns (uint160) {
        return Slot0Library.sqrtPriceX96(packed);
    }

    function getTick(Slot0 packed) external view returns (int24) {
        return Slot0Library.tick(packed);
    }

    function getProtocolFee(Slot0 packed) external view returns (uint24) {
        return Slot0Library.protocolFee(packed);
    }

    function getLpFee(Slot0 packed) external view returns (uint24) {
        return Slot0Library.lpFee(packed);
    }
}
