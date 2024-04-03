// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";

contract TestCurrency is Test {
    using CurrencyLibrary for *;

    uint256 constant initialERC20Balance = 1000 ether;
    uint256 constant sentBalance = 2 ether;
    address constant otherAddress = address(1);

    Currency nativeCurrency;
    Currency erc20Currency;

    function setUp() public {
        assert(address(this).balance > 0);
        nativeCurrency = Currency.wrap(address(0));
        MockERC20 token = new MockERC20("TestA", "A", 18);
        token.mint(address(this), initialERC20Balance);
        erc20Currency = Currency.wrap(address(token));
    }

    function test_fuzz_balanceOfSelf_native(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        nativeCurrency.transfer(otherAddress, amount);
        assertEq(nativeCurrency.balanceOfSelf(), address(this).balance);
    }

    function test_fuzz_balanceOfSelf_token(uint256 amount) public {
        amount = bound(amount, 0, initialERC20Balance);
        erc20Currency.transfer(otherAddress, amount);
        assertEq(erc20Currency.balanceOfSelf(), initialERC20Balance - amount);
    }

    function test_fuzz_balanceOf_native(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        nativeCurrency.transfer(otherAddress, amount);

        assertEq(nativeCurrency.balanceOf(otherAddress), amount);
    }

    function test_fuzz_balanceOf_token(uint256 amount) public {
        amount = bound(amount, 0, initialERC20Balance);
        erc20Currency.transfer(otherAddress, amount);
        assertEq(erc20Currency.balanceOf(otherAddress), amount);
    }

    function test_isNative_native_returnsTrue() public {
        assertEq(nativeCurrency.isNative(), true);
    }

    function test_isNative_token_returnsFalse() public {
        assertEq(erc20Currency.isNative(), false);
    }

    function test_fuzz_isNative(Currency currency) public {
        assertEq(currency.isNative(), (Currency.unwrap(currency) == address(0)));
    }

    function test_toId_nativeReturns0() public {
        assertEq(nativeCurrency.toId(), uint256(0));
    }

    function test_fuzz_toId_returnsCurrencyAsUint256(Currency currency) public {
        assertEq(currency.toId(), uint256(uint160(Currency.unwrap(currency))));
    }

    function test_fromId_0ReturnsNative() public {
        assertEq(Currency.unwrap(uint256(0).fromId()), Currency.unwrap(nativeCurrency));
    }

    function test_fuzz_fromId_returnsUint256AsCurrency(uint256 id) public {
        uint160 expectedCurrency = uint160(uint256(type(uint160).max) & id);
        assertEq(Currency.unwrap(id.fromId()), address(expectedCurrency));
    }

    function test_fuzz_fromId_toId_opposites(Currency currency) public {
        assertEq(Currency.unwrap(currency), Currency.unwrap(currency.toId().fromId()));
    }

    function test_fuzz_transfer_native_successfullyTransfersFunds(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);

        uint256 balanceBefore = otherAddress.balance;
        nativeCurrency.transfer(otherAddress, amount);
        uint256 balanceAfter = otherAddress.balance;

        assertEq(balanceAfter - balanceBefore, amount);
    }

    function test_fuzz_transfer_token_successfullyTransfersFunds(uint256 amount) public {
        amount = bound(amount, 0, initialERC20Balance);

        uint256 balanceBefore = erc20Currency.balanceOf(otherAddress);
        erc20Currency.transfer(otherAddress, amount);
        uint256 balanceAfter = erc20Currency.balanceOf(otherAddress);

        assertEq(balanceAfter - balanceBefore, amount);
    }
}
