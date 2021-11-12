// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';

/// @notice Holds the state for all pools
contract PoolManager {
    using SafeCast for *;
    using Pool for *;

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower token of the pool, sorted numerically
        IERC20Minimal token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20Minimal token1;
        /// @notice The fee for the pool
        uint24 fee;
    }

    struct FeeConfig {
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
    }

    mapping(bytes32 => Pool.State) public pools;
    mapping(uint24 => FeeConfig) public configs;

    constructor() {
        _configure(100, 1);
        _configure(500, 10);
        _configure(3000, 60);
        _configure(10000, 200);
    }

    function _configure(uint24 fee, int24 tickSpacing) internal {
        require(tickSpacing > 0);
        require(configs[fee].tickSpacing == 0);
        configs[fee].tickSpacing = tickSpacing;
        configs[fee].maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
        // todo: emit event
    }

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(key))];
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external {
        _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96);
    }

    function increaseObservationCardinalityNext(PoolKey memory key, uint16 observationCardinalityNext)
        external
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
    {
        (observationCardinalityNextOld, observationCardinalityNextNew) = _getPool(key)
            .increaseObservationCardinalityNext(observationCardinalityNext);
    }

    struct MintParams {
        // the address that will receive the liquidity
        address recipient;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        uint256 amount;
    }

    /// @dev Mint some liquidity for the given pool
    function mint(PoolKey memory key, MintParams memory params) external returns (uint256 amount0, uint256 amount1) {
        require(params.amount > 0);

        FeeConfig memory config = configs[key.fee];

        Pool.BalanceDelta memory result = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: params.recipient,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: config.maxLiquidityPerTick,
                tickSpacing: config.tickSpacing
            })
        );

        amount0 = uint256(result.amount0);
        amount1 = uint256(result.amount1);

        // todo: account the delta via the vault
    }

    struct BurnParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        uint256 amount;
    }

    /// @dev Mint some liquidity for the given pool
    function burn(PoolKey memory key, BurnParams memory params) external returns (uint256 amount0, uint256 amount1) {
        require(params.amount > 0);

        FeeConfig memory config = configs[key.fee];

        // todo: where to get maxLiquidityPerTick, tickSpacing, probably from storage
        Pool.BalanceDelta memory result = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: -int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: config.maxLiquidityPerTick,
                tickSpacing: config.tickSpacing
            })
        );

        amount0 = uint256(-result.amount0);
        amount1 = uint256(-result.amount1);

        // todo: account the delta via the vault
    }

    struct SwapParams {
        address recipient;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        bytes data;
    }

    function swap(PoolKey memory key, SwapParams memory params) external returns (int256 amount0, int256 amount1) {
        FeeConfig memory config = configs[key.fee];

        Pool.BalanceDelta memory result = _getPool(key).swap(
            Pool.SwapParams({
                time: _blockTimestamp(),
                recipient: params.recipient,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                data: params.data,
                fee: key.fee,
                tickSpacing: config.tickSpacing
            })
        );

        (amount0, amount1) = (result.amount0, result.amount1);

        // todo: account the delta via the vault
    }

    function observe(PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return _getPool(key).observe(_blockTimestamp(), secondsAgos);
    }

    function snapshotCumulativesInside(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (Pool.Snapshot memory) {
        return _getPool(key).snapshotCumulativesInside(tickLower, tickUpper, _blockTimestamp());
    }
}
