// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from './external/IERC20Minimal.sol';
import {Pool} from '../libraries/Pool.sol';
import {IPoolImplementation} from './IPoolImplementation.sol';

interface IPoolManager {
    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower token of the pool, sorted numerically
        IERC20Minimal token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20Minimal token1;
        /// @notice The implementation of the pool to use for the swap
        IPoolImplementation poolImplementation;
    }

    /// @notice Returns the reserves for a given ERC20 token
    function reservesOf(IERC20Minimal token) external view returns (uint256);

    struct MintParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        uint256 amount;
    }

    /// @notice Represents the address that has currently locked the pool
    function lockedBy() external view returns (address);

    function tokensTouched(uint256 index) external view returns (IERC20Minimal);

    function tokenDelta(IERC20Minimal token) external view returns (uint8, int248);

    /// @notice All operations go through this function
    function lock(bytes calldata data) external returns (bytes memory);

    /// @dev Mint some liquidity for the given pool
    function mint(PoolKey memory key, MintParams memory params) external returns (Pool.BalanceDelta memory delta);

    struct BurnParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // the reduction in liquidity to effect
        uint256 amount;
    }

    /// @dev Mint some liquidity for the given pool
    function burn(PoolKey memory key, BurnParams memory params) external returns (Pool.BalanceDelta memory delta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function swap(PoolKey memory key, SwapParams memory params) external returns (Pool.BalanceDelta memory delta);

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external;

    /// @notice Called by the user to pay what is owed
    function settle(IERC20Minimal token) external returns (uint256 paid);
}
