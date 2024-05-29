// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";
import {CustomRevert} from "./CustomRevert.sol";

library Reserves {
    using CustomRevert for bytes4;

    /// bytes32(uint256(keccak256("ReservesOf")) - 1)
    bytes32 constant RESERVES_OF_SLOT = 0x1e0745a7db1623981f0b2a5d4232364c00787266eb75ad546f190e6cebe9bd95;
    /// @notice The transient reserves for pools with no balance is set to the max as a sentinel to track that it has been synced.
    uint256 public constant ZERO_BALANCE = type(uint256).max;

    /// @notice Thrown when someone has not called sync before calling settle for the first time.
    error ReservesMustBeSynced();

    function setReserves(Currency currency, uint256 value) internal {
        if (value == 0) value = ZERO_BALANCE;
        bytes32 key = _getKey(currency);
        assembly {
            tstore(key, value)
        }
    }

    function getReserves(Currency currency) internal view returns (uint256 value) {
        bytes32 key = _getKey(currency);
        assembly {
            value := tload(key)
        }
        if (value == 0) ReservesMustBeSynced.selector.revertWith();
        if (value == ZERO_BALANCE) value = 0;
    }

    function _getKey(Currency currency) private pure returns (bytes32 key) {
        assembly ("memory-safe") {
            mstore(0, RESERVES_OF_SLOT)
            mstore(32, currency)
            key := keccak256(0, 64)
        }
    }
}
