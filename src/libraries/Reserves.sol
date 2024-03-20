// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";

library Reserves {
    using CurrencyLibrary for Currency;

    uint256 constant RESERVES_OF_SLOT = uint256(keccak256("ReservesOf")) - 1;

    function set(Currency currency, uint256 value) internal {
        bytes32 key = _getKey(currency);
        assembly {
            tstore(key, value)
        }
    }

    function get(Currency currency) internal view returns (uint256 value) {
        bytes32 key = _getKey(currency);
        assembly {
            value := tload(key)
        }
    }

    function _getKey(Currency currency) private pure returns (bytes32 key) {
        uint256 slot = RESERVES_OF_SLOT;
        assembly {
            mstore(0, slot)
            mstore(32, currency)
            key := keccak256(0, 64)
        }
    }
}
