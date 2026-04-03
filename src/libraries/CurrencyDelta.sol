// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";

/// @title CurrencyDelta
/// @notice A library to store callers' currency deltas in transient storage
/// @dev This library implements the equivalent of a mapping, as transient storage can only be accessed in assembly.
/// Currency deltas track the balance changes for each (account, currency) pair during an unlock callback.
/// Positive deltas mean the account is owed tokens by the pool, negative means they owe tokens to the pool.
/// All deltas must be settled (reach zero) before the unlock completes.
/// @custom:security Transient storage is automatically cleared at the end of each transaction.
library CurrencyDelta {
    /// @notice Calculates the transient storage slot for a given account and currency delta
    /// @dev Uses keccak256(target || currency) to derive a unique slot for each (account, currency) pair.
    /// This prevents collisions between different accounts and currencies.
    /// @param target The address whose delta is being tracked
    /// @param currency The currency for which the delta is being tracked
    /// @return hashSlot The computed storage slot
    function _computeSlot(address target, Currency currency) internal pure returns (bytes32 hashSlot) {
        assembly ("memory-safe") {
            // Store target address in first 32 bytes (right-padded), masking to 160 bits
            mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
            // Store currency address in second 32 bytes, masking to 160 bits
            mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            // Hash both values together to get unique slot
            hashSlot := keccak256(0, 64)
        }
    }

    /// @notice Gets the current delta for a currency and account
    /// @dev Reads from transient storage at the computed slot
    /// @param currency The currency to check
    /// @param target The account to check
    /// @return delta The current delta (positive = owed to account, negative = owed by account)
    function getDelta(Currency currency, address target) internal view returns (int256 delta) {
        bytes32 hashSlot = _computeSlot(target, currency);
        assembly ("memory-safe") {
            // Load delta from transient storage
            delta := tload(hashSlot)
        }
    }

    /// @notice Applies a new currency delta for a given account and currency
    /// @dev Adds the delta to the existing value in transient storage
    /// @param currency The currency being modified
    /// @param target The account whose delta is being modified
    /// @param delta The amount to add to the current delta (can be negative)
    /// @return previous The prior delta value
    /// @return next The new delta value after applying the change
    function applyDelta(Currency currency, address target, int128 delta)
        internal
        returns (int256 previous, int256 next)
    {
        bytes32 hashSlot = _computeSlot(target, currency);

        assembly ("memory-safe") {
            // Load current delta
            previous := tload(hashSlot)
        }
        // Compute new delta (addition happens outside assembly for clarity)
        next = previous + delta;
        assembly ("memory-safe") {
            // Store updated delta
            tstore(hashSlot, next)
        }
    }
}
