// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from './CurrencyLibrary.sol';

struct CurrencyDelta {
    Currency currency;
    int256 delta;
}

/// @title CurrencyDeltaMapping
/// @dev Implements an in-memory mapping for Currencies to their current deltas
// TODO: this library currently expands memory with reckless abandon
// it could be improved by managing memory more effectively, ideas:
// - batch mem allocation, i.e. allocate 5 slots at a time, use one if currency == 0
// - re-use cleared slots, i.e. if delta == 0 we can safely overwrite
// - check if freemempointer is at the end of the current array and just pushing + updating size + updating fmp
// - use a linked list or something else
library CurrencyDeltaMapping {
    using CurrencyLibrary for Currency;

    /// @notice put the given delta into the mapping for currency
    /// @dev using memory array to implement mapping-like behavior
    function add(
        CurrencyDelta[] memory deltas,
        Currency currency,
        int256 delta
    ) internal pure returns (CurrencyDelta[] memory result) {
        // if currency already exists in deltas, just update it
        for (uint256 i = 0; i < deltas.length; i++) {
            if (deltas[i].currency.equals(currency)) {
                deltas[i].delta += delta;
                return deltas;
            }
        }

        // else we have to expand the mapping
        result = new CurrencyDelta[](deltas.length + 1);
        for (uint256 i = 0; i < deltas.length; i++) {
            result[i] = deltas[i];
        }
        result[deltas.length] = CurrencyDelta(currency, delta);
    }

    /// @notice returns the value at currency, 0 if not yet set
    function get(CurrencyDelta[] memory deltas, Currency currency) internal pure returns (int256) {
        // if currency already exists in deltas, just update it
        for (uint256 i = 0; i < deltas.length; i++) {
            if (deltas[i].currency.equals(currency)) {
                return deltas[i].delta;
            }
        }
        return 0;
    }
}
