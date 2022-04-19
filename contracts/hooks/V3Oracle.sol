// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {Oracle} from '../libraries/Oracle.sol';

/// @notice Includes the Oracle feature in a similar way to V3. This is now externalized
contract V3Oracle is IHooks {
    using Oracle for Oracle.Observation[65535];

    struct ObservationState {
        uint16 index;
        uint16 cardinality;
        uint16 cardinalityNext;
    }

    mapping(bytes32 => Oracle.Observation[65535]) private observations;
    mapping(bytes32 => ObservationState) public states;

    /// @notice The address of the pool manager
    IPoolManager public immutable poolManager;

    /// @dev For mocking
    function _blockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    constructor(IPoolManager _poolManager) {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false
            })
        );
        poolManager = _poolManager;
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey memory,
        uint160
    ) external pure override {
        revert();
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey memory key,
        uint160,
        int24
    ) external override {
        bytes32 id = keccak256(abi.encode(key));
        (states[id].cardinality, states[id].cardinalityNext) = observations[id].initialize(_blockTimestamp());
    }

    /// @dev Called before any action that potentially modifies pool price or liquidity, such as swap or modify position
    function _updatePool(IPoolManager.PoolKey memory key) private {
        (, int24 tick) = poolManager.getSlot0(key);

        uint128 liquidity = poolManager.getLiquidity(key);

        bytes32 id = keccak256(abi.encode(key));

        (states[id].index, states[id].cardinality) = observations[id].write(
            states[id].index,
            _blockTimestamp(),
            tick,
            liquidity,
            states[id].cardinality,
            states[id].cardinalityNext
        );
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata
    ) external override {
        _updatePool(key);
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override {
        revert();
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata
    ) external override {
        _updatePool(key);
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override {
        revert();
    }

    /// @notice Observe the given pool for the timestamps
    function observe(IPoolManager.PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        bytes32 id = keccak256(abi.encode(key));

        ObservationState memory state = states[id];

        (, int24 tick) = poolManager.getSlot0(key);

        uint128 liquidity = poolManager.getLiquidity(key);

        return
            observations[id].observe(_blockTimestamp(), secondsAgos, tick, state.index, liquidity, state.cardinality);
    }

    /// @notice Increase the cardinality target for the given pool
    function increaseCardinalityNext(IPoolManager.PoolKey calldata key, uint16 cardinalityNext)
        external
        returns (uint16 cardinalityNextOld, uint16 cardinalityNextNew)
    {
        bytes32 id = keccak256(abi.encode(key));

        ObservationState storage state = states[id];

        cardinalityNextOld = state.cardinalityNext;
        cardinalityNextNew = observations[id].grow(cardinalityNextOld, cardinalityNext);
        state.cardinalityNext = cardinalityNextNew;
    }
}
