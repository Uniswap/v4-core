// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

library CurrencyDelta {
    // Equivalent to uint256(keccak256("CurrencyDelta")) - 1;
    uint256 constant CURRENCY_DELTA_SLOT = uint256(0x95b400a0305233758f18c75aa62cbbb5d6882951dd55f1407390ee7b6924e26d);

    function _computeSlot(address caller_, Currency currency) internal pure returns (bytes32 hashSlot) {
        uint256 slot = CURRENCY_DELTA_SLOT;

        assembly {
            mstore(0, caller_)
            mstore(32, slot)
            let intermediateHash := keccak256(0, 64)

            mstore(0, intermediateHash)
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
