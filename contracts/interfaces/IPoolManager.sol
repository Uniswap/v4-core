// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from './external/IERC20Minimal.sol';
import {Pool} from '../libraries/Pool.sol';
import {IHooks} from './IHooks.sol';

interface IPoolManager {
    /// @notice Thrown when tokens touched has exceeded max of 256
    error MaxTokensTouched();

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
        /// @notice Ticks that involve positions must be a multiple of tick spacing
        int24 tickSpacing;
        /// @notice The hooks of the pool
        IHooks hooks;
    }

    /// @notice Represents a change in the pool's balance of token0 and token1.
    /// @dev This is returned from most pool operations
    struct BalanceDelta {
        int256 amount0;
        int256 amount1;
    }

    /// @notice Returns the reserves for a given ERC20 token
    function reservesOf(IERC20Minimal token) external view returns (uint256);

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(PoolKey memory key, uint16 observationCardinalityNext)
        external
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew);

    /// @notice Represents the stack of addresses that have locked the pool. Each call to #lock pushes the address onto the stack
    /// @param index The index of the locker, also known as the id of the locker
    function lockedBy(uint256 index) external view returns (address);

    /// @notice Getter for the length of the lockedBy array
    function lockedByLength() external view returns (uint256);

    /// @notice Get the number of tokens touched for the given locker index. The current locker index is always `#lockedByLength() - 1`
    /// @param id The ID of the locker
    function getTokensTouchedLength(uint256 id) external view returns (uint256);

    /// @notice Get the token touched at the given index for the given locker index
    /// @param id The ID of the locker
    /// @param index The index of the token in the tokens touched array to get
    function getTokensTouched(uint256 id, uint256 index) external view returns (IERC20Minimal);

    /// @notice Get the current delta for a given token, and its position in the tokens touched array
    /// @param id The ID of the locker
    /// @param token The token for which to lookup the delta
    function getTokenDelta(uint256 id, IERC20Minimal token) external view returns (uint8 slot, int248 delta);

    /// @notice All operations go through this function
    /// @param data Any data to pass to the callback, via `ILockCallback(msg.sender).lockCallback(data)`
    /// @return The data returned by the call to `ILockCallback(msg.sender).lockCallback(data)`
    function lock(bytes calldata data) external returns (bytes memory);

    struct ModifyPositionParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // how to modify the liquidity
        int256 liquidityDelta;
    }

    /// @notice Modify the position for the given pool
    function modifyPosition(PoolKey memory key, ModifyPositionParams memory params)
        external
        returns (IPoolManager.BalanceDelta memory delta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swap against the given pool
    function swap(PoolKey memory key, SwapParams memory params)
        external
        returns (IPoolManager.BalanceDelta memory delta);

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
