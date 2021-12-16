// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from './external/IERC20Minimal.sol';
import {Pool} from '../libraries/Pool.sol';
import {IPoolImplementation} from './IPoolImplementation.sol';

import {BalanceDelta} from './shared.sol';

interface IPoolManager {
    struct Pair {
        /// @notice The lower token of the pool, sorted numerically
        IERC20Minimal token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20Minimal token1;
    }

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The token pair
        Pair pair;
        /// @notice The implementation of the pool to use for the swap
        IPoolImplementation poolImplementation;
    }

    /// @notice Returns the reserves for a given ERC20 token
    function reservesOf(IERC20Minimal token) external view returns (uint256);

    ///////////////////////    TRANSIENT STATE   ///////////////////////////////////

    /// @notice The address that has locked the pool
    function lockedBy() external view returns (address);

    /// @notice The tokens that have been touched by any pool operations
    function tokensTouched(uint256 index) external view returns (IERC20Minimal);

    /// @notice The deltas and indices for each token touched by any operations in the pool. All deltas must be 0 at the end of the lock.
    function tokenDelta(IERC20Minimal token) external view returns (uint8, int248);

    /////////////////////// TRANSIENT STATE ENDS ///////////////////////////////////

    /// @notice All the below operations must happen in the context of a lock. Locks can be acquired by calling this function.
    /// @param data Any data to be passed through to the lock callback
    function lock(bytes calldata data) external returns (bytes memory);

    /// @notice Modify a position in a pool
    /// @param key The key of the pool for which to mint
    /// @param data How to modify the position, encoded for the pool implementation specified in the pool key
    function modifyPosition(PoolKey memory key, bytes memory data) external returns (BalanceDelta memory delta);

    /// @dev Execute a swap against the given pool
    /// @param key The key of the pool to swap against
    /// @param data How to swap against the pool, encoded for the pool implementation specified in the pool key
    function swap(PoolKey memory key, bytes memory data) external returns (BalanceDelta memory delta);

    /// @notice Take some tokens out of the manager
    /// @dev Can also be used for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external;

    /// @notice Account for some tokens sent to the manager
    function settle(IERC20Minimal token) external returns (uint256 paid);
}
