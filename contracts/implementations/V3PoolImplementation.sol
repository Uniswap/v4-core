// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from '../libraries/Pool.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IV3PoolImplementation} from '../interfaces/implementations/IV3PoolImplementation.sol';
import {NoDelegateCall} from '../NoDelegateCall.sol';

contract V3PoolImplementation is IV3PoolImplementation, NoDelegateCall {
    using Pool for *;

    /// @inheritdoc IV3PoolImplementation
    uint24 public immutable override fee;
    /// @inheritdoc IV3PoolImplementation
    int24 public immutable override tickSpacing;
    /// @inheritdoc IV3PoolImplementation
    uint128 public immutable override maxLiquidityPerTick;

    // todo: can we make this documented in the interface
    mapping(bytes32 => Pool.State) public pools;

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(IERC20Minimal token0, IERC20Minimal token1) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(token0, token1))];
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
