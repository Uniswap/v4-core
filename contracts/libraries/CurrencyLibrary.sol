// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {TransferHelper} from './TransferHelper.sol';

type Currency is address;

/// @title CurrencyLibrary
/// @dev This library allows for transferring and holding native ETH and ERC20 tokens
library CurrencyLibrary {
    using TransferHelper for IERC20Minimal;
    using CurrencyLibrary for Currency;

    address constant NATIVE = address(0);

    function transfer(
        Currency currency,
        address to,
        uint256 amount
    ) internal {
        if (currency.isNative()) {
            TransferHelper.safeTransferETH(to, amount);
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).safeTransfer(to, amount);
        }
    }

    function balanceOf(Currency currency, address who) internal view returns (uint256) {
        if (currency.isNative()) {
            return who.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(who);
        }
    }

    function equals(Currency currency, Currency other) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(other);
    }

    function isNative(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == NATIVE;
    }

    function toId(Currency currency) internal pure returns (uint256) {
        return uint256(uint160(Currency.unwrap(currency)));
    }

    function fromId(uint256 id) internal pure returns (Currency) {
        return Currency.wrap(address(uint160(id)));
    }
}
