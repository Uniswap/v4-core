// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from './libraries/Pool.sol';
import {SafeCast} from './libraries/SafeCast.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';

contract SingletonPool {
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

    mapping(bytes32 => Pool.State) public pools;

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

        // todo: where to get maxLiquidityPerTick, tickSpacing, probably from storage
        Pool.ModifyPositionResult memory result = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: params.recipient,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: type(uint128).max,
                tickSpacing: 60
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

        // todo: where to get maxLiquidityPerTick, tickSpacing, probably from storage
        Pool.ModifyPositionResult memory result = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: -int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: type(uint128).max,
                tickSpacing: 60
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
        Pool.SwapResult memory result = _getPool(key).swap(
            Pool.SwapParams({
                time: _blockTimestamp(),
                fee: key.fee,
                recipient: params.recipient,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                data: params.data,
                tickSpacing: 60
            })
        );

        (amount0, amount1) = (result.amount0, result.amount1);

        // todo: account the delta via the vault
    }
}
