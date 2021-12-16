// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from '../libraries/Pool.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IV3PoolImplementation} from '../interfaces/implementations/IV3PoolImplementation.sol';
import {NoDelegateCall} from '../NoDelegateCall.sol';
import {BasePoolImplementation} from './base/BasePoolImplementation.sol';
import {Tick} from '../libraries/Tick.sol';
import {BalanceDelta} from '../interfaces/shared.sol';

contract V3PoolImplementation is IV3PoolImplementation, BasePoolImplementation, NoDelegateCall {
    using Pool for *;

    /// @inheritdoc IV3PoolImplementation
    uint24 public immutable override fee;
    /// @inheritdoc IV3PoolImplementation
    int24 public immutable override tickSpacing;
    /// @inheritdoc IV3PoolImplementation
    uint128 public immutable override maxLiquidityPerTick;

    constructor(
        IPoolManager _manager,
        uint24 _fee,
        int24 _tickSpacing
    ) BasePoolImplementation(_manager) {
        fee = _fee;
        tickSpacing = _tickSpacing;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    // todo: can we make this documented in the interface
    mapping(bytes32 => Pool.State) public pools;

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(IERC20Minimal token0, IERC20Minimal token1) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(token0, token1))];
    }

    function modifyPosition(
        address sender,
        IPoolManager.Pair memory pair,
        bytes memory data
    ) external override managerOnly returns (BalanceDelta memory) {
        IV3PoolImplementation.ModifyPositionParams memory params = abi.decode(
            data,
            (IV3PoolImplementation.ModifyPositionParams)
        );
        return
            _getPool(pair.token0, pair.token1).modifyPosition(
                Pool.ModifyPositionParams({
                    owner: params.owner,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    liquidityDelta: int128(params.liquidityDelta),
                    time: _blockTimestamp(),
                    maxLiquidityPerTick: maxLiquidityPerTick,
                    tickSpacing: tickSpacing
                })
            );
    }

    function swap(
        address sender,
        IPoolManager.Pair memory pair,
        bytes memory data
    ) external override managerOnly returns (BalanceDelta memory) {
        IV3PoolImplementation.SwapParams memory params = abi.decode(data, (IV3PoolImplementation.SwapParams));
        return
            _getPool(pair.token0, pair.token1).swap(
                Pool.SwapParams({
                    fee: fee,
                    tickSpacing: tickSpacing,
                    time: _blockTimestamp(),
                    zeroForOne: params.zeroForOne,
                    amountSpecified: params.amountSpecified,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint160 sqrtPriceX96
    ) external override returns (int24 tick) {
        tick = _getPool(token0, token1).initialize(_blockTimestamp(), sqrtPriceX96);
    }

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint16 observationCardinalityNext
    ) external override returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew) {
        (observationCardinalityNextOld, observationCardinalityNextNew) = _getPool(token0, token1)
            .increaseObservationCardinalityNext(observationCardinalityNext);
    }

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint8 feeProtocol
    ) external override returns (uint8 feeProtocolOld) {
        return _getPool(token0, token1).setFeeProtocol(feeProtocol);
    }

    /// @notice Observe a past state of a pool
    function observe(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint32[] calldata secondsAgos
    )
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return _getPool(token0, token1).observe(_blockTimestamp(), secondsAgos);
    }

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        IERC20Minimal token0,
        IERC20Minimal token1,
        int24 tickLower,
        int24 tickUpper
    ) external view override noDelegateCall returns (Pool.Snapshot memory) {
        return _getPool(token0, token1).snapshotCumulativesInside(tickLower, tickUpper, _blockTimestamp());
    }
}
