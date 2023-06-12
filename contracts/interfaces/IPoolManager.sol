// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Currency} from "../libraries/CurrencyLibrary.sol";
import {Pool} from "../libraries/Pool.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IHooks} from "./IHooks.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

interface IPoolManager is IERC1155 {
    /// @notice Thrown when currencies touched has exceeded max of 256
    error MaxCurrenciesTouched();

    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();

    /// @notice Thrown when a currency is not netted out after a lock
    error CurrencyNotSettled();

    /// @notice Thrown when a function is called by an address that is not the current locker
    /// @param locker The current locker
    error LockedBy(address locker);

    /// @notice The ERC1155 being deposited is not the Uniswap ERC1155
    error NotPoolManagerToken();

    /// @notice Pools must have a fee that is <100%, enforced in #intialize and for dynamic fee pools
    error FeeTooLarge();

    /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
    error TickSpacingTooLarge();
    /// @notice Pools must have a positive non-zero tickSpacing passed to #initialize
    error TickSpacingTooSmall();

    /// @notice Emitted when a new pool is initialized
    /// @param poolId The abi encoded hash of the pool key struct for the new pool
    /// @param currency0 The first currency of the pool by address sort order
    /// @param currency1 The second currency of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    event Initialize(
        bytes32 indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
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
        bytes32 indexed poolId, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );

    /// @notice Emitted for swaps between currency0 and currency1
    /// @param poolId The abi encoded hash of the pool key struct for the pool that was modified
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param amount0 The delta of the currency0 balance of the pool
    /// @param amount1 The delta of the currency1 balance of the pool
    /// @param sqrtPriceX96 The sqrt(price) of the pool after the swap, as a Q64.96
    /// @param liquidity The liquidity of the pool after the swap
    /// @param tick The log base 1.0001 of the price of the pool after the swap
    event Swap(
        bytes32 indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event ProtocolFeeUpdated(bytes32 indexed poolKey, uint8 protocolSwapFee, uint8 protocolWithdrawFee);

    event ProtocolFeeControllerUpdated(address protocolFeeController);

    event HookFeeUpdated(bytes32 indexed poolKey, uint8 hookSwapFee, uint8 hookWithdrawFee);

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower currency of the pool, sorted numerically
        Currency currency0;
        /// @notice The higher currency of the pool, sorted numerically
        Currency currency1;
        /// @notice The pool swap fee, capped at 1_000_000. The upper 4 bits determine if the hook sets any fees.
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

    /// @notice Returns the minimum denominator for the protocol fee, which restricts it to a maximum of 25%
    function MIN_PROTOCOL_FEE_DENOMINATOR() external view returns (uint8);

    /// @notice Get the current value in slot0 of the given pool
    function getSlot0(bytes32 id)
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolSwapFee,
            uint8 protocolWithdrawFee,
            uint8 hookSwapFee,
            uint8 hookWithdrawFee
        );

    /// @notice Get the current value of liquidity of the given pool
    function getLiquidity(bytes32 id) external view returns (uint128 liquidity);

    /// @notice Get the current value of liquidity for the specified pool and position
    function getLiquidity(bytes32 id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint128 liquidity);

    // @notice Given a currency address, returns the protocol fees accrued in that currency
    function protocolFeesAccrued(Currency) external view returns (uint256);

    /// @notice Returns the reserves for a given ERC20 currency
    function reservesOf(Currency currency) external view returns (uint256);

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Represents the stack of addresses that have locked the pool. Each call to #lock pushes the address onto the stack
    /// @param index The index of the locker, also known as the id of the locker
    function lockedBy(uint256 index) external view returns (address);

    /// @notice Getter for the length of the lockedBy array
    function lockedByLength() external view returns (uint256);

    /// @notice Returns the count of nonzero deltas for the given locker ID
    /// @param id The ID of the locker
    function getNonzeroDeltaCount(uint256 id) external view returns (uint256);

    /// @notice Get the current delta for a given currency, and its position in the currencies touched array
    /// @param id The ID of the locker
    /// @param currency The currency for which to lookup the delta
    function getCurrencyDelta(uint256 id, Currency currency) external view returns (int256);

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
    function modifyPosition(PoolKey memory key, ModifyPositionParams memory params) external returns (BalanceDelta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swap against the given pool
    function swap(PoolKey memory key, SwapParams memory params) external returns (BalanceDelta);

    /// @notice Donate the given currency amounts to the pool with the given pool key
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1) external returns (BalanceDelta);

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Called by the user to move value into ERC1155 balance
    function mint(Currency token, address to, uint256 amount) external;

    /// @notice Called by the user to pay what is owed
    function settle(Currency token) external payable returns (uint256 paid);

    /// @notice Sets the protocol's swap and withdrawal fees for the given pool
    /// Protocol fees are always a portion of a fee that is owed. If that underlying fee is 0, no protocol fees will accrue even if it is set to > 0.
    function setProtocolFees(PoolKey memory key) external;

    /// @notice Sets the hook's swap and withdrawal fees for the given pool
    function setHookFees(PoolKey memory key) external;

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to sload
    /// @return value The value of the slot as bytes32
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to start sloading from
    /// @param nSlots Number of slots to load into return value
    /// @return value The value of the sload-ed slots concatentated as dynamic bytes
    function extsload(bytes32 slot, uint256 nSlots) external view returns (bytes memory value);
}
