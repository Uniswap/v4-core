// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Pool} from './libraries/Pool.sol';
import {SafeCast} from './libraries/SafeCast.sol';

contract SingletonPool {
    using SafeCast for *;
    using Pool for *;

    mapping(bytes32 => Pool.State) public pools;

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(Pool.Key memory key) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(key))];
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(Pool.Key memory key, uint160 sqrtPriceX96) external {
        _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96);
    }

    function increaseObservationCardinalityNext(Pool.Key memory key, uint16 observationCardinalityNext)
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
    function mint(Pool.Key memory key, MintParams memory params) external returns (uint256 amount0, uint256 amount1) {
        require(params.amount > 0);

        //        (int256 amount0Int, int256 amount1Int) = _getPool(key).modifyPosition(
        //            Pool.ModifyPositionParams({
        //                owner: params.recipient,
        //                tickLower: params.tickLower,
        //                tickUpper: params.tickUpper,
        //                liquidityDelta: int256(uint256(params.amount)).toInt128(),
        //                time: _blockTimestamp(),
        //    // todo: where to get these, probably from storage
        //                maxLiquidityPerTick: type(uint128).max,
        //                tickSpacing: 60
        //            })
        //        );
        //
        //        amount0 = uint256(amount0Int);
        //        amount1 = uint256(amount1Int);

        // todo: account the delta via the vault
    }
}
