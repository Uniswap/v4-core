// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Pool} from "../libraries/Pool.sol";
import {IHooks} from "./IHooks.sol";
import {IERC6909Claims} from "./external/IERC6909Claims.sol";
import {IProtocolFees} from "./IProtocolFees.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolId} from "../types/PoolId.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolManager is IProtocolFees, IERC6909Claims {
    /// @notice Thrown when currencies touched has exceeded max of 256
    error MaxCurrenciesTouched();

    /// @notice Thrown when a currency is not netted out after a lock
    error CurrencyNotSettled();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when lock is called, but a lock is already open
    error AlreadyLocked();

    /// @notice Thrown when a function is called outside of a lock
    error ManagerNotLocked();

    /// @notice The ERC1155 being deposited is not the Uniswap ERC1155
    error NotPoolManagerToken();

    /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
    error TickSpacingTooLarge();
    /// @notice Pools must have a positive non-zero tickSpacing passed to #initialize
    error TickSpacingTooSmall();

    /// @notice PoolKey must have currencies where address(currency0) < address(currency1)
    error CurrenciesOutOfOrderOrEqual();

    /// @notice Thrown when a call to updateDynamicSwapFee is made by an address that is not the hook,
    /// or on a pool that does not have a dynamic swap fee.
    error UnauthorizedDynamicSwapFeeUpdate();

    /// @notice Emitted when a new pool is initialized
    /// @param id The abi encoded hash of the pool key struct for the new pool
    /// @param currency0 The first currency of the pool by address sort order
    /// @param currency1 The second currency of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    /// @notice Emitted when a liquidity position is modified
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that modified the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The amount of liquidity that was added or removed
    event ModifyLiquidity(
        PoolId indexed id, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );

    /// @notice Emitted for swaps between currency0 and currency1
    /// @param id The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param amount0 The delta of the currency0 balance of the pool
    /// @param amount1 The delta of the currency1 balance of the pool
    /// @param sqrtPriceX96 The sqrt(price) of the pool after the swap, as a Q64.96
    /// @param liquidity The liquidity of the pool after the swap
    /// @param tick The log base 1.0001 of the price of the pool after the swap
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event ProtocolFeeUpdated(PoolId indexed id, uint16 protocolFee);

    /// @notice Returns the constant representing the maximum tickSpacing for an initialized pool key
    function MAX_TICK_SPACING() external view returns (int24);

    /// @notice Returns the constant representing the minimum tickSpacing for an initialized pool key
    function MIN_TICK_SPACING() external view returns (int24);

    /// @notice Get the current value in slot0 of the given pool
    function getSlot0(PoolId id)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 swapFee);

    /// @notice Get the current value of liquidity of the given pool
    function getLiquidity(PoolId id) external view returns (uint128 liquidity);

    /// @notice Get the current value of liquidity for the specified pool and position
    function getLiquidity(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint128 liquidity);

    /// @notice Getter for TickInfo for the given poolId and tick
    function getPoolTickInfo(PoolId id, int24 tick) external view returns (Pool.TickInfo memory);

    /// @notice Getter for the bitmap given the poolId and word position
    function getPoolBitmapInfo(PoolId id, int16 word) external view returns (uint256 tickBitmap);

    /// @notice Get the position struct for a specified pool and position
    function getPosition(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        returns (Position.Info memory position);

    /// @notice Returns the reserves for a given ERC20 currency
    function reservesOf(Currency currency) external view returns (uint256);

    /// @notice Returns whether the contract is locked
    function isLockSet() external view returns (bool);

    /// @notice Returns the number of nonzero deltas open on the PoolManager that must be zerod by the close of the initial lock.
    function getLockNonzeroDeltaCount() external view returns (uint256 _nonzeroDeltaCount);

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        returns (int24 tick);

    /// @notice Get the current delta for a caller in the given currency
    /// @param caller The address of the caller
    /// @param currency The currency for which to lookup the delta
    function currencyDelta(address caller, Currency currency) external view returns (int256);

    /// @notice All operations go through this function
    /// @param data Any data to pass to the callback, via `ILockCallback(msg.sender).lockAcquired(data)`
    /// @return The data returned by the call to `ILockCallback(msg.sender).lockAcquired(data)`
    function lock(bytes calldata data) external payable returns (bytes memory);

    struct ModifyLiquidityParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // how to modify the liquidity
        int256 liquidityDelta;
    }

    /// @notice Modify the liquidity for the given pool
    /// @dev Poke by calling with a zero liquidityDelta
    /// @param key The pool to modify liquidity in
    /// @param params The parameters for modifying the liquidity
    /// @param hookData Any data to pass to the callback, via `ILockCallback(msg.sender).lockAcquired(data)`
    /// @return delta The balance delta of the liquidity
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swap against the given pool
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta);

    /// @notice Donate the given currency amounts to the pool with the given pool key
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (BalanceDelta);

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Called by the user to move value into ERC6909 balance
    function mint(address to, uint256 id, uint256 amount) external;

    /// @notice Called by the user to move value from ERC6909 balance
    function burn(address from, uint256 id, uint256 amount) external;

    /// @notice Called by the user to pay what is owed
    function settle(Currency token) external payable returns (uint256 paid);

    /// @notice Sets the protocol's swap fee for the given pool
    /// Protocol fees are always a portion of the LP swap fee that is owed. If that fee is 0, no protocol fees will accrue even if it is set to > 0.
    function setProtocolFee(PoolKey memory key) external;

    /// @notice Updates the pools swap fees for the a pool that has enabled dynamic swap fees.
    function updateDynamicSwapFee(PoolKey memory key, uint24 newDynamicSwapFee) external;

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to sload
    /// @return value The value of the slot as bytes32
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to start sloading from
    /// @param nSlots Number of slots to load into return value
    /// @return value The value of the sload-ed slots concatenated as dynamic bytes
    function extsload(bytes32 slot, uint256 nSlots) external view returns (bytes memory value);
}
