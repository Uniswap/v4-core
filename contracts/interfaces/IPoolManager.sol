// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from './external/IERC20Minimal.sol';
import {Pool} from '../libraries/Pool.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IHooks} from './IHooks.sol';

interface IPoolManager is IERC1155 {
    /// @notice Thrown when tokens touched has exceeded max of 256
    error MaxTokensTouched();

    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();

    /// @notice Thrown when a token is owed to the caller or the caller owes a token
    /// @param token The token that is owed
    /// @param delta The amount that is owed by or to the locker
    error TokenNotSettled(IERC20Minimal token, int256 delta);

    /// @notice Thrown when a function is called by an address that is not the current locker
    /// @param locker The current locker
    error LockedBy(address locker);

    /// @notice The ERC1155 being deposited is not the Uniswap ERC1155
    error NotPoolManagerToken();

    /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
    error TickSpacingTooLarge();
    /// @notice Pools must have a positive non-zero tickSpacing passed to #initialize
    error TickSpacingTooSmall();

    /// @notice Emitted when a new pool is initialized
    /// @param poolId The abi encoded hash of the pool key struct for the new pool
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    event Initialize(
        bytes32 indexed poolId,
        IERC20Minimal indexed token0,
        IERC20Minimal indexed token1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    /// @notice Emitted when a liquidity position is modified
    /// @param poolId The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that modified the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The amount of liquidity that was added or removed
    event ModifyPosition(
        bytes32 indexed poolId,
        address indexed sender,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    );

    /// @notice Emitted for swaps between token0 and token1
    /// @param poolId The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param amount0 The delta of the token0 balance of the pool
    /// @param amount1 The delta of the token1 balance of the pool
    /// @param sqrtPriceX96 The sqrt(price) of the pool after the swap, as a Q64.96
    /// @param liquidity The liquidity of the pool after the swap
    /// @param tick The log base 1.0001 of the price of the pool after the swap
    event Swap(
        bytes32 indexed poolId,
        address indexed sender,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    event ProtocolFeeUpdated(bytes32 indexed poolKey, uint8 protocolFee);

    event ProtocolFeeControllerUpdated(address protocolFeeController);

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

    /// @notice Returns the constant representing the maximum tickSpacing for an initialized pool key
    function MAX_TICK_SPACING() external view returns (int24);

    /// @notice Returns the constant representing the minimum tickSpacing for an initialized pool key
    function MIN_TICK_SPACING() external view returns (int24);

    /// @notice Get the current value in slot0 of the given pool
    function getSlot0(bytes32 id)
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolFee
        );

    /// @notice Get the current value of liquidity of the given pool
    function getLiquidity(bytes32 id) external view returns (uint128 liquidity);

    /// @notice Get the current value of liquidity for the specified pool and position
    function getLiquidity(
        bytes32 id,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint128 liquidity);

    // @notice Given a token address, returns the protocol fees accrued in that token
    function protocolFeesAccrued(IERC20Minimal) external view returns (uint256);

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
    function getTokenDelta(uint256 id, IERC20Minimal token) external view returns (uint8 index, int248 delta);

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
        returns (BalanceDelta memory delta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swap against the given pool
    function swap(PoolKey memory key, SwapParams memory params) external returns (BalanceDelta memory delta);

    /// @notice Donate the given token amounts to the pool with the given pool key
    function donate(
        PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) external returns (BalanceDelta memory delta);

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external;

    /// @notice Called by the user to move value into ERC1155 balance
    function mint(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external;

    /// @notice Called by the user to pay what is owed
    function settle(IERC20Minimal token) external returns (uint256 paid);

    /// @notice sets the protocol fee for the given pool
    function setPoolProtocolFee(PoolKey memory key) external;
}
