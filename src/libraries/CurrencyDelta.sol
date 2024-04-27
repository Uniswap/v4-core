// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

library CurrencyDelta {
    function _computeSlot(address caller_, Currency currency) internal pure returns (bytes32 hashSlot) {
        assembly {
            mstore(0, caller_)
            mstore(32, currency)
            hashSlot := keccak256(0, 64)
        }
    }

    function setDelta(Currency currency, address caller, int256 delta) internal {
        bytes32 hashSlot = _computeSlot(caller, currency);

        assembly {
            tstore(hashSlot, delta)
        }
    }

    function getDelta(Currency currency, address caller) internal view returns (int256 delta) {
        bytes32 hashSlot = _computeSlot(caller, currency);

        assembly {
            delta := tload(hashSlot)
        }
    }
}
