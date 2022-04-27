// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {TickMath} from '../libraries/TickMath.sol';
import {Oracle} from '../libraries/Oracle.sol';
import {BaseHook} from './base/BaseHook.sol';

/// @notice A hook for a pool that allows a Uniswap pool to act as an oracle. Pools that use this hook must have full range
///     tick spacing and liquidity is always permanently locked in these pools. This is the suggested configuration
///     for protocols that wish to use a V3 style geomean oracle.
contract GeomeanOracle is BaseHook {
    using Oracle for Oracle.Observation[65535];

    /// @notice Oracle pools do not have fees because they exist to serve as an oracle for a pair of tokens
    error OnlyOneOraclePoolAllowed();

    /// @notice Oracle positions must be full range
    error OraclePositionsMustBeFullRange();

    /// @notice Oracle pools must have liquidity locked so that they cannot become more susceptible to price manipulation
    error OraclePoolMustLockLiquidity();

    /// @member index The index of the last written observation for the pool
    /// @member cardinality The cardinality of the observations array for the pool
    /// @member cardinalityNext The cardinality target of the observations array for the pool, which will replace cardinality when enough observations are written
    struct ObservationState {
        uint16 index;
        uint16 cardinality;
        uint16 cardinalityNext;
    }

    /// @notice The list of observations for a given pool ID
    mapping(bytes32 => Oracle.Observation[65535]) public observations;
    /// @notice The current observation array state for the given pool ID
    mapping(bytes32 => ObservationState) public states;

    /// @notice Returns the observation for the given pool key and observation index
    function getObservation(IPoolManager.PoolKey calldata key, uint256 index)
        external
        view
        returns (Oracle.Observation memory observation)
    {
        observation = observations[keccak256(abi.encode(key))][index];
    }

    /// @notice Returns the state for the given pool key
    function getState(IPoolManager.PoolKey calldata key) external view returns (ObservationState memory state) {
        state = states[keccak256(abi.encode(key))];
    }

    /// @dev For mocking
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160
    ) external view override poolManagerOnly {
        // This is to limit the fragmentation of pools using this oracle hook. In other words,
        // there may only be one pool per pair of tokens that use this hook. The tick spacing is set to the maximum
        // because we only allow max range liquidity in this pool.
        if (key.fee != 0 || key.tickSpacing != poolManager.MAX_TICK_SPACING()) revert OnlyOneOraclePoolAllowed();
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160,
        int24
    ) external override poolManagerOnly {
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
        IPoolManager.ModifyPositionParams calldata params
    ) external override poolManagerOnly {
        if (params.liquidityDelta < 0) revert OraclePoolMustLockLiquidity();
        int24 maxTickSpacing = poolManager.MAX_TICK_SPACING();
        if (
            params.tickLower != TickMath.minUsableTick(maxTickSpacing) ||
            params.tickUpper != TickMath.maxUsableTick(maxTickSpacing)
        ) revert OraclePositionsMustBeFullRange();
        _updatePool(key);
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata
    ) external override poolManagerOnly {
        _updatePool(key);
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
