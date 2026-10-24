// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @title CurrencyReserves
/// @author Uniswap Labs
/// @notice Library for managing synced currency and reserve tracking using EIP-1153 transient storage
/// @dev This library provides transient storage (TSTORE/TLOAD) operations for tracking
/// the currently synced currency and its reserves during a transaction. Transient storage
/// is automatically cleared at the end of each transaction, making it ideal for
/// temporary state that only needs to persist within a single transaction.
///
/// The library uses namespaced storage slots calculated as `keccak256(name) - 1` to avoid
/// collisions with other storage variables.
///
/// Key concepts:
/// - Synced currency: The currency being tracked for balance verification
/// - Reserves: The expected balance of the synced currency
/// - These values are used to verify that balance changes match expected deltas
library CurrencyReserves {
    using CustomRevert for bytes4;

    /// @dev The transient storage slot holding the reserves of the synced currency.
    /// @dev Calculated as `bytes32(uint256(keccak256("ReservesOf")) - 1)` to effectively
    /// namespace the slot and avoid collisions with other storage variables.
    bytes32 constant RESERVES_OF_SLOT = 0x1e0745a7db1623981f0b2a5d4232364c00787266eb75ad546f190e6cebe9bd95;

    /// @dev The transient storage slot holding the currently synced currency address.
    /// @dev Calculated as `bytes32(uint256(keccak256("Currency")) - 1)` to effectively
    /// namespace the slot and avoid collisions with other storage variables.
    bytes32 constant CURRENCY_SLOT = 0x27e098c505d44ec3574004bca052aabf76bd35004c182099d8c575fb238593b9;

    /// @notice Retrieves the currently synced currency from transient storage
    /// @dev Uses TLOAD opcode (EIP-1153) to read from transient storage.
    /// The value is automatically cleared at the end of the transaction.
    /// @return currency The Currency type representing the synced currency address
    function getSyncedCurrency() internal view returns (Currency currency) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // TLOAD reads from transient storage at CURRENCY_SLOT
            currency := tload(CURRENCY_SLOT)
        }
    }

    /// @notice Resets the synced currency to address(0) in transient storage
    /// @dev Uses TSTORE opcode (EIP-1153) to clear the currency slot.
    /// This is typically called after completing sync verification to clean up state.
    function resetCurrency() internal {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // TSTORE writes 0 to clear the transient storage slot
            tstore(CURRENCY_SLOT, 0)
        }
    }

    /// @notice Atomically sets both the synced currency and its reserves in transient storage
    /// @dev Uses TSTORE opcode (EIP-1153) to write to transient storage.
    /// The currency address is masked to 160 bits to ensure proper address formatting.
    /// Both values are set in a single function call to maintain consistency.
    /// @param currency The currency to sync (will be masked to 160 bits)
    /// @param value The reserve amount to store for the synced currency
    function syncCurrencyAndReserves(Currency currency, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Mask currency to 160 bits (address size) and store in CURRENCY_SLOT
            tstore(CURRENCY_SLOT, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            // Store the reserve value in RESERVES_OF_SLOT
            tstore(RESERVES_OF_SLOT, value)
        }
    }

    /// @notice Retrieves the current reserves of the synced currency from transient storage
    /// @dev Uses TLOAD opcode (EIP-1153) to read from transient storage.
    /// This value represents the expected/tracked balance of the synced currency.
    /// @return value The reserve amount stored for the synced currency
    function getSyncedReserves() internal view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // TLOAD reads from transient storage at RESERVES_OF_SLOT
            value := tload(RESERVES_OF_SLOT)
        }
    }
}
