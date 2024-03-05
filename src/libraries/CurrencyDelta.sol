// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

library CurrencyDelta {
    uint256 constant CURRENCY_DELTA_SLOT = uint256(keccak256("CurrencyDelta")) - 1;

    function setCurrencyDelta(address locker, Currency currency, int256 delta) internal {
        uint256 slot = CURRENCY_DELTA_SLOT;

        assembly {
            mstore(0, locker)
            mstore(32, slot)
            let intermediateHash := keccak256(0, 64)

            mstore(0, intermediateHash)
            mstore(32, currency)
            let hashSlot := keccak256(0, 64)

            tstore(hashSlot, delta)
        }
    }

    function getCurrencyDelta(address locker, Currency currency) internal view returns (int256 delta) {
        uint256 slot = CURRENCY_DELTA_SLOT;

        assembly {
            mstore(0, locker)
            mstore(32, slot)
            let intermediateHash := keccak256(0, 64)

            mstore(0, intermediateHash)
            mstore(32, currency)
            let hashSlot := keccak256(0, 64)

            delta := tload(hashSlot)
        }
    }
}
