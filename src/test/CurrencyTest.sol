// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";

contract CurrencyTest {
    function transfer(Currency currency, address to, uint256 amount) external {
        currency.transfer(to, amount);
    }

    function balanceOfSelf(Currency currency) external view returns (uint256) {
        return currency.balanceOfSelf();
    }

    function balanceOf(Currency currency, address owner) external view returns (uint256) {
        return currency.balanceOf(owner);
    }

    function isNative(Currency currency) external pure returns (bool) {
        return currency.isNative();
    }

    function toId(Currency currency) external pure returns (uint256) {
        return currency.toId();
    }

    function fromId(uint256 id) external pure returns (Currency) {
        return CurrencyLibrary.fromId(id);
    }
}
