// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {V46909} from "../V46909.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

/// @notice Mock contract for testing V46909
contract MockV46909 is V46909 {
    using CurrencyLibrary for Currency;

    /// @notice mocked mint logic without delta accounting
    function mint(address to, Currency currency, uint256 amount) public {
        _mint(to, currency.toId(), amount);
    }

    /// @notice mocked burn logic without delta accounting and without checking allowance
    function burnFrom(address from, Currency currency, uint256 amount) public {
        _burnFrom(from, currency.toId(), amount);
    }
}
