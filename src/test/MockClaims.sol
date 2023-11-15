// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Claims} from "../Claims.sol";
import {IClaims} from "../interfaces/IClaims.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

contract MockClaims is Claims {
    using CurrencyLibrary for Currency;

    function mint(address to, Currency currency, uint256 amount) public {
        _mint(to, currency, amount);
    }

    function burn(Currency currency, uint256 amount) public {
        _burn(currency, amount);
    }
}
