// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

library CurrencyDelta {
    uint256 constant CURRENCY_DELTA_SLOT = uint256(keccak256("CurrencyDelta")) - 1;

    function _computeSlot(address locker, Currency currency) internal pure returns (bytes32 hashSlot) {
        uint256 slot = CURRENCY_DELTA_SLOT;

        assembly {
            mstore(0, locker)
            mstore(32, slot)
            let intermediateHash := keccak256(0, 64)

            mstore(0, intermediateHash)
            mstore(32, currency)
            hashSlot := keccak256(0, 64)
        }
    }

    function set(address locker, Currency currency, int256 delta) internal {
        bytes32 hashSlot = _computeSlot(locker, currency);

        assembly {
            tstore(hashSlot, delta)
        }
    }

    function get(address locker, Currency currency) internal view returns (int256 delta) {
        bytes32 hashSlot = _computeSlot(locker, currency);

        assembly {
            delta := tload(hashSlot)
        }
    }
}
