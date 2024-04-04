// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";

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
        MockERC20 token = new MockERC20("TestA", "A", 18);
        token.mint(address(this), initialERC20Balance);
        erc20Currency = Currency.wrap(address(token));
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

    function testCurrency_transfer_native_successfullyTransfersFunds() public {
        uint256 balanceBefore = otherAddress.balance;
        nativeCurrency.transfer(otherAddress, sentBalance);
        uint256 balanceAfter = otherAddress.balance;

        assertEq(balanceAfter - balanceBefore, sentBalance);
    }

    function testCurrency_transfer_token_successfullyTransfersFunds() public {
        uint256 balanceBefore = erc20Currency.balanceOf(otherAddress);
        erc20Currency.transfer(otherAddress, sentBalance);
        uint256 balanceAfter = erc20Currency.balanceOf(otherAddress);

        assertEq(balanceAfter - balanceBefore, sentBalance);
    }
}
