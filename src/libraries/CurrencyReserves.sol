// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";
import {CustomRevert} from "./CustomRevert.sol";

library CurrencyReserves {
    using CustomRevert for bytes4;

    /// @notice Thrown when a user has already synced a currency, but not yet settled
    error AlreadySynced();

    /// bytes32(uint256(keccak256("ReservesOf")) - 1)
    bytes32 constant RESERVES_OF_SLOT = 0x1e0745a7db1623981f0b2a5d4232364c00787266eb75ad546f190e6cebe9bd95;
    /// bytes32(uint256(keccak256("Sync")) - 1)
    bytes32 constant CURRENCY_SLOT = 0xf0e14a408baf7f453312eec68e9b7d728ec5337fbdf671f917ee8c80f3255231;

    function requireNotSynced() internal view {
        Currency currencySynced;
        assembly {
            currencySynced := tload(CURRENCY_SLOT)
        }
        if (!currencySynced.isZero()) {
            AlreadySynced.selector.revertWith();
        }
    }

    function getSyncedCurrency() internal view returns (Currency currency) {
        assembly {
            currency := tload(CURRENCY_SLOT)
        }
    }

    function reset() internal {
        assembly {
            tstore(CURRENCY_SLOT, 0)
        }
    }

    function syncCurrencyAndReserves(Currency currency, uint256 value) internal {
        assembly {
            tstore(CURRENCY_SLOT, currency)
            tstore(RESERVES_OF_SLOT, value)
        }
    }

    function getSyncedReserves() internal view returns (uint256 value) {
        assembly {
            value := tload(RESERVES_OF_SLOT)
        }
    }
}
