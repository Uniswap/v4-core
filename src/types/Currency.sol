// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

type Currency is address;

using {greaterThan as >, lessThan as <, greaterThanOrEqualTo as >=, equals as ==} for Currency global;
using CurrencyLibrary for Currency global;

function equals(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) == Currency.unwrap(other);
}

function greaterThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) > Currency.unwrap(other);
}

function lessThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) < Currency.unwrap(other);
}

function greaterThanOrEqualTo(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) >= Currency.unwrap(other);
}

/// @title CurrencyLibrary
/// @dev This library allows for transferring and holding native tokens and ERC20 tokens
library CurrencyLibrary {
    /// @notice Thrown when a native transfer fails
    error NativeTransferFailed();

    /// @notice Thrown when an ERC20 transfer fails
    error ERC20TransferFailed();

    Currency public constant NATIVE = Currency.wrap(address(0));

    function transfer(Currency currency, address to, uint256 amount) internal {
        // altered from https://github.com/Vectorized/solady/blob/89101d53b7c8784cca935c1f2f6403639cee48b2/src/utils/SafeTransferLib.sol
        // modified custom error selectors

        if (currency.isNative()) {
            assembly ("memory-safe") {
                // Transfer the ETH and revert if it fails.
                if iszero(call(gas(), to, amount, 0x00, 0x00, 0x00, 0x00)) {
                    mstore(0x00, 0xf4b3b1bc) // `NativeTransferFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        } else {
            assembly ("memory-safe") {
                mstore(0x14, to) // Store the `to` address in [0x20, 0x34).
                mstore(0x34, amount) // Store the `amount` argument in [0x34, 0x54).
                // Store the selector of `transfer(address,uint256)` in [0x10, 0x14).
                // also cleans the upper bits of `to`
                mstore(0x00, 0xa9059cbb000000000000000000000000)
                // Perform the transfer, reverting upon failure.
                if iszero(
                    and( // The arguments of `and` are evaluated from right to left.
                        or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                        call(gas(), currency, 0, 0x10, 0x44, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0xf27f64e4) // `ERC20TransferFailed()`.
                    revert(0x1c, 0x04)
                }
                mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
            }
        }
    }

    function balanceOfSelf(Currency currency) internal view returns (uint256) {
        if (currency.isNative()) {
            return address(this).balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(address(this));
        }
    }

    function balanceOf(Currency currency, address owner) internal view returns (uint256) {
        if (currency.isNative()) {
            return owner.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(owner);
        }
    }

    function isNative(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(NATIVE);
    }

    function toId(Currency currency) internal pure returns (uint256) {
        return uint160(Currency.unwrap(currency));
    }

    function fromId(uint256 id) internal pure returns (Currency) {
        return Currency.wrap(address(uint160(id)));
    }
}
