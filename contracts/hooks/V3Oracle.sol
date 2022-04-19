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
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96
    ) external override {
        revert();
    }

    function afterInitialize(
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external override {
        bytes32 id = keccak256(abi.encode(key));
        (states[id].cardinality, states[id].cardinalityNext) = observations[id].initialize(_blockTimestamp());
    }

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override {
        revert('TODO: implement');
    }

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        IPoolManager.BalanceDelta calldata delta
    ) external override {
        revert();
    }

    function beforeSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override {
        revert('TODO: implement');
    }

    function afterSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        IPoolManager.BalanceDelta calldata delta
    ) external override {
        revert();
    }

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
