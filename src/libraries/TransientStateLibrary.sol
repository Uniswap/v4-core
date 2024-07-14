// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {PoolId} from "../types/PoolId.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../types/Currency.sol";
import {Position} from "./Position.sol";
import {CurrencyReserves} from "./CurrencyReserves.sol";
import {NonZeroDeltaCount} from "./NonZeroDeltaCount.sol";
import {Lock} from "./Lock.sol";

library TransientStateLibrary {
    /// @notice returns the reserves for the synced currency
    /// @param manager The pool manager contract.
    /// @return uint256 The reserves of the currency.
    /// @dev returns 0 if the reserves are not synced or value is 0.
    /// Checks the synced currency to only return valid reserve values (after a sync and before a settle).
    function getSyncedReserves(IPoolManager manager) internal view returns (uint256) {
        if (getSyncedCurrency(manager).isZero()) return 0;
        return uint256(manager.exttload(CurrencyReserves.RESERVES_OF_SLOT));
    }

    function getSyncedCurrency(IPoolManager manager) internal view returns (Currency) {
        return Currency.wrap(address(uint160(uint256(manager.exttload(CurrencyReserves.CURRENCY_SLOT)))));
    }

    /// @notice Returns the number of nonzero deltas open on the PoolManager that must be zerod out before the contract is locked
    function getNonzeroDeltaCount(IPoolManager manager) internal view returns (uint256) {
        return uint256(manager.exttload(NonZeroDeltaCount.NONZERO_DELTA_COUNT_SLOT));
    }

    /// @notice Get the current delta for a caller in the given currency
    /// @param caller_ The address of the caller
    /// @param currency The currency for which to lookup the delta
    function currencyDelta(IPoolManager manager, address caller_, Currency currency) internal view returns (int256) {
        bytes32 key;
        assembly ("memory-safe") {
            mstore(0, caller_)
            mstore(32, currency)
            key := keccak256(0, 64)
        }
        return int256(uint256(manager.exttload(key)));
    }

    /// @notice Returns whether the contract is unlocked or not
    function isUnlocked(IPoolManager manager) internal view returns (bool) {
        return manager.exttload(Lock.IS_UNLOCKED_SLOT) != 0x0;
    }
}
