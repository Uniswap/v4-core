// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

/// @title Currency
/// @notice A user-defined value type wrapping an address to represent a currency (native ETH or ERC20 token)
/// @dev Currency wraps an address where:
/// - address(0) represents the native currency (ETH on Ethereum mainnet)
/// - Any other address represents an ERC20 token contract
///
/// This type provides type-safety and prevents accidental mixing of addresses and currencies.
/// Global operators (==, >, <, >=) are defined for direct comparison.
/// The CurrencyLibrary provides utility functions for transfers and balance queries.
type Currency is address;

using {greaterThan as >, lessThan as <, greaterThanOrEqualTo as >=, equals as ==} for Currency global;
using CurrencyLibrary for Currency global;

/// @notice Checks if two currencies are equal by comparing their underlying addresses
/// @param currency The first currency to compare
/// @param other The second currency to compare
/// @return True if both currencies have the same underlying address
function equals(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) == Currency.unwrap(other);
}

/// @notice Checks if the first currency's address is greater than the second
/// @dev Used for sorting currencies in pool keys where currency0 < currency1 is required
/// @param currency The first currency to compare
/// @param other The second currency to compare
/// @return True if currency's address is numerically greater than other's address
function greaterThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) > Currency.unwrap(other);
}

/// @notice Checks if the first currency's address is less than the second
/// @dev Used for sorting currencies in pool keys where currency0 < currency1 is required
/// @param currency The first currency to compare
/// @param other The second currency to compare
/// @return True if currency's address is numerically less than other's address
function lessThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) < Currency.unwrap(other);
}

/// @notice Checks if the first currency's address is greater than or equal to the second
/// @param currency The first currency to compare
/// @param other The second currency to compare
/// @return True if currency's address is numerically greater than or equal to other's address
function greaterThanOrEqualTo(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) >= Currency.unwrap(other);
}

/// @title CurrencyLibrary
/// @author Uniswap Labs
/// @notice Library for transferring and querying balances of native ETH and ERC20 tokens
/// @dev This library provides a unified interface for handling both native currency (ETH)
/// and ERC20 tokens. It uses optimized assembly for gas efficiency and follows
/// ERC-7751 for enhanced error handling with wrapped errors.
///
/// Key features:
/// - Unified transfer interface for native ETH and ERC20 tokens
/// - Gas-optimized ERC20 transfers using inline assembly
/// - Balance queries for both self and arbitrary addresses
/// - Currency ID conversion for efficient storage
library CurrencyLibrary {
    /// @notice Additional context for ERC-7751 wrapped error when a native transfer fails
    /// @dev Thrown when an ETH transfer via CALL opcode returns false
    error NativeTransferFailed();

    /// @notice Additional context for ERC-7751 wrapped error when an ERC20 transfer fails
    /// @dev Thrown when an ERC20 transfer call fails or returns false
    error ERC20TransferFailed();

    /// @notice A constant representing the native currency (ETH on mainnet)
    /// @dev address(0) is used to represent native ETH throughout the protocol
    Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));

    /// @notice Transfers currency (native ETH or ERC20) to a recipient
    /// @dev For native ETH: uses CALL opcode with value
    /// For ERC20: uses optimized assembly to call transfer(address,uint256)
    /// On failure, bubbles up the error with ERC-7751 wrapped context
    /// @param currency The currency to transfer (address(0) for native ETH)
    /// @param to The recipient address
    /// @param amount The amount to transfer (in wei for ETH, smallest unit for ERC20)
    function transfer(Currency currency, address to, uint256 amount) internal {
        // altered from https://github.com/transmissions11/solmate/blob/44a9963d4c78111f77caa0e65d677b8b46d6f2e6/src/utils/SafeTransferLib.sol
        // modified custom error selectors

        bool success;
        if (currency.isAddressZero()) {
            assembly ("memory-safe") {
                // Transfer the ETH and revert if it fails.
                success := call(gas(), to, amount, 0, 0, 0, 0)
            }
            // revert with NativeTransferFailed, containing the bubbled up error as an argument
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(to, bytes4(0), NativeTransferFailed.selector);
            }
        } else {
            assembly ("memory-safe") {
                // Get a pointer to some free memory.
                let fmp := mload(0x40)

                // Write the abi-encoded calldata into memory, beginning with the function selector.
                mstore(fmp, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                mstore(add(fmp, 4), and(to, 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to" argument.
                mstore(add(fmp, 36), amount) // Append the "amount" argument. Masking not required as it's a full 32 byte type.

                success :=
                    and(
                        // Set success to whether the call reverted, if not we check it either
                        // returned exactly 1 (can't just be non-zero data), or had no return data.
                        or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                        // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                        // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                        // Counterintuitively, this call must be positioned second to the or() call in the
                        // surrounding and() call or else returndatasize() will be zero during the computation.
                        call(gas(), currency, 0, fmp, 68, 0, 32)
                    )

                // Now clean the memory we used
                mstore(fmp, 0) // 4 byte `selector` and 28 bytes of `to` were stored here
                mstore(add(fmp, 0x20), 0) // 4 bytes of `to` and 28 bytes of `amount` were stored here
                mstore(add(fmp, 0x40), 0) // 4 bytes of `amount` were stored here
            }
            // revert with ERC20TransferFailed, containing the bubbled up error as an argument
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(
                    Currency.unwrap(currency), IERC20Minimal.transfer.selector, ERC20TransferFailed.selector
                );
            }
        }
    }

    /// @notice Gets the balance of the currency held by the current contract
    /// @dev For native ETH: returns address(this).balance
    /// For ERC20: calls balanceOf(address(this)) on the token contract
    /// @param currency The currency to query (address(0) for native ETH)
    /// @return The balance of the currency held by this contract
    function balanceOfSelf(Currency currency) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return address(this).balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(address(this));
        }
    }

    /// @notice Gets the balance of the currency held by a specific address
    /// @dev For native ETH: returns owner.balance
    /// For ERC20: calls balanceOf(owner) on the token contract
    /// @param currency The currency to query (address(0) for native ETH)
    /// @param owner The address to query the balance of
    /// @return The balance of the currency held by the owner
    function balanceOf(Currency currency, address owner) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return owner.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(owner);
        }
    }

    /// @notice Checks if the currency represents native ETH (address(0))
    /// @param currency The currency to check
    /// @return True if the currency is the native currency (address(0))
    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(ADDRESS_ZERO);
    }

    /// @notice Converts a Currency to a uint256 ID for efficient storage
    /// @dev Simply casts the underlying address to uint160, then to uint256
    /// This is useful for using Currency as a mapping key
    /// @param currency The currency to convert
    /// @return The currency represented as a uint256 (only lower 160 bits used)
    function toId(Currency currency) internal pure returns (uint256) {
        return uint160(Currency.unwrap(currency));
    }

    /// @notice Converts a uint256 ID back to a Currency
    /// @dev Casts the uint256 to uint160, then wraps as an address
    /// WARNING: If the upper 12 bytes of id are non-zero, they will be truncated.
    /// Therefore, fromId(toId(currency)) == currency, but toId(fromId(id)) may not equal id
    /// if the original id had non-zero upper bytes.
    /// @param id The uint256 to convert (only lower 160 bits are used)
    /// @return The Currency wrapping the address derived from the lower 160 bits
    function fromId(uint256 id) internal pure returns (Currency) {
        return Currency.wrap(address(uint160(id)));
    }
}
