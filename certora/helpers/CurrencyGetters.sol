// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Currency } from "src/types/Currency.sol";
import { BalanceDeltaLibrary, BalanceDelta } from "src/types/BalanceDelta.sol";

contract CurrencyGetters {
    function fromCurrency(Currency currency) public pure returns (address) {
        return Currency.unwrap(currency);
    }

    function toCurrency(address token) public pure returns (Currency) {
        return Currency.wrap(token);
    }

    function amount0(BalanceDelta balanceDelta) external pure returns (int128) {
        return BalanceDeltaLibrary.amount0(balanceDelta);
    }

    function amount1(BalanceDelta balanceDelta) external pure returns (int128) {
        return BalanceDeltaLibrary.amount1(balanceDelta);
    }
}
