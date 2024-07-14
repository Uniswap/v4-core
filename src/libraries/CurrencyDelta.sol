// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

/// @title a library to store callers' currency deltas in transient storage
/// @dev this library implements the equivalent of a mapping, as transient storage can only be accessed in assembly
library CurrencyDelta {
    /// @notice calculates which storage slot a delta should be stored in for a given account and currency
    function _computeSlot(address target, Currency currency) internal pure returns (bytes32 hashSlot) {
        assembly ("memory-safe") {
            mstore(0, target)
            mstore(32, currency)
            hashSlot := keccak256(0, 64)
        }
    }

    /// @notice applies a new currency delta for a given account and currency
    /// @return previous the prior value
    /// @return next the modified result
    function applyDelta(Currency currency, address target, int128 delta)
        internal
        returns (int256 previous, int256 next)
    {
        bytes32 hashSlot = _computeSlot(target, currency);

        assembly {
            previous := tload(hashSlot)
        }
        next = previous + delta;
        assembly {
            tstore(hashSlot, next)
        }
    }
}
