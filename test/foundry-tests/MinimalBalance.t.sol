// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {MinimalBalance} from "../../contracts/MinimalBalance.sol";
import {IMinimalBalance} from "../../contracts/interfaces/IMinimalBalance.sol";
import {CurrencyLibrary, Currency} from "../../contracts/types/Currency.sol";

contract MockMinimalBalanceImpl is MinimalBalance {
    using CurrencyLibrary for Currency;

    function mint(address to, Currency currency, uint256 amount) public {
        _mint(to, currency.toId(), amount);
    }

    function burn(Currency currency, uint256 amount) public {
        _burn(currency.toId(), amount);
    }
}

contract MinimalBalanceTest is TokenFixture, Test {
    using CurrencyLibrary for Currency;

    MockMinimalBalanceImpl minimalBalanceImpl = new MockMinimalBalanceImpl();

    event Mint(address indexed to, uint256 indexed id, uint256 amount);
    event Burn(address indexed from, uint256 indexed id, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed id, uint256 amount);

    function setUp() public {}

    function testCanBurn(uint256 amount) public {
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectEmit(true, true, false, false);
        emit Burn(address(this), currency0.toId(), amount);
        minimalBalanceImpl.burn(currency0, amount);
    }

    function testCatchesUnderflowOnBurn(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(abi.encodeWithSelector(IMinimalBalance.InsufficientBalance.selector));
        minimalBalanceImpl.burn(currency0, amount + 1);
    }

    function testCanTransfer(uint256 amount) public {
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(this), address(1), currency0.toId(), amount);
        minimalBalanceImpl.transfer(address(1), currency0, amount);
    }

    function testCatchesUnderflowOnTransfer(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(abi.encodeWithSelector(IMinimalBalance.InsufficientBalance.selector));
        minimalBalanceImpl.transfer(address(1), currency0, amount + 1);
    }

    function testCatchesOverflowOnTransfer() public {
        minimalBalanceImpl.mint(address(0xdead), currency0, type(uint256).max);
        minimalBalanceImpl.mint(address(this), currency0, 1);
        // transfer will revert since overflow
        vm.expectRevert();
        minimalBalanceImpl.transfer(address(0xdead), currency0, 1);
    }
}
