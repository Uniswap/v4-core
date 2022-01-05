// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from './external/IERC20Minimal.sol';
import {Pool} from '../libraries/Pool.sol';

interface IPoolManager {
    /// @notice Thrown when a token is owed to the caller or the caller owes a token
    /// @param token The token that is owed
    /// @param delta The amount that is owed by or to the locker
    error TokenNotSettled(IERC20Minimal token, int256 delta);

    /// @notice Thrown when a function is called by an address that is not the current locker
    /// @param locker The current locker
    error LockedBy(address locker);

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower token of the pool, sorted numerically
        IERC20Minimal token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20Minimal token1;
        /// @notice The fee for the pool
        uint24 fee;
    }

    /// @notice Returns the immutable configuration for a given fee
    function configs(uint24 fee) external view returns (int24 tickSpacing, uint128 maxLiquidityPerTick);

    /// @notice Returns the reserves for a given ERC20 token
    function reservesOf(IERC20Minimal token) external view returns (uint256);

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(PoolKey memory key, uint16 observationCardinalityNext)
        external
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew);

    struct MintParams {
        // the address that will own the minted liquidity
        address recipient;
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

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(PoolKey calldata key, uint8 feeProtocol) external returns (uint8 feeProtocolOld);

    /// @notice Observe a past state of a pool
    function observe(PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (Pool.Snapshot memory);
}
