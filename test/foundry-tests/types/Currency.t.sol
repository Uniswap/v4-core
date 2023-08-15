// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../../contracts/types/Currency.sol";

contract TestCurrency is Test {
    using CurrencyLibrary for Currency;
    using CurrencyLibrary for uint256;

    uint256 constant initialERC20Balance = 1000 ether;
    uint256 constant sentBalance = 2 ether;
    address constant otherAddress = address(1);

    Currency nativeCurrency;
    Currency erc20Currency;

    function setUp() public {
        nativeCurrency = Currency.wrap(address(0));
        erc20Currency = Currency.wrap(address(new MockERC20("TestA", "A", 18, initialERC20Balance)));
        erc20Currency.transfer(address(1), sentBalance);
        nativeCurrency.transfer(address(1), sentBalance);
    }

    function testCurrency_balanceOfSelf_native() public {
        assertEq(nativeCurrency.balanceOfSelf(), address(this).balance);
    }

    function testCurrency_balanceOfSelf_token() public {
        assertEq(erc20Currency.balanceOfSelf(), initialERC20Balance - sentBalance);
    }

    function testCurrency_balanceOf_native() public {
        assertEq(nativeCurrency.balanceOf(otherAddress), sentBalance);
    }

    function testCurrency_balanceOf_token() public {
        assertEq(erc20Currency.balanceOf(otherAddress), sentBalance);
    }

    function testCurrency_isNative_native_returnsTrue() public {
        assertEq(nativeCurrency.isNative(), true);
    }

    function testCurrency_isNative_token_returnsFalse() public {
        assertEq(erc20Currency.isNative(), false);
    }

    function testCurrency_toId_native_returns0() public {
        assertEq(nativeCurrency.toId(), uint256(0));
    }

    function testCurrency_toId_token_returnsAddressAsUint160() public {
        assertEq(erc20Currency.toId(), uint256(uint160(Currency.unwrap(erc20Currency))));
    }

    function testCurrency_fromId_native_returns0() public {
        assertEq(Currency.unwrap(uint256(0).fromId()), Currency.unwrap(nativeCurrency));
    }

    function testCurrency_fromId_token_returnsAddressAsUint160() public {
        assertEq(
            Currency.unwrap(uint256(uint160(Currency.unwrap(erc20Currency))).fromId()), Currency.unwrap(erc20Currency)
        );
    }
}
