// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {MinimalBalance} from "../../contracts/MinimalBalance.sol";
import {IMinimalBalance} from "../../contracts/interfaces/IMinimalBalance.sol";
import {CurrencyLibrary, Currency} from "../../contracts/types/Currency.sol";

contract MinimalBalanceImpl is MinimalBalance {
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

    MinimalBalanceImpl minimalBalanceImpl = new MinimalBalanceImpl();

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
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(stdError.arithmeticError);
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
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        minimalBalanceImpl.mint(address(this), currency0, amount);

        assertEq(minimalBalanceImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(stdError.arithmeticError);
        minimalBalanceImpl.transfer(address(1), currency0, amount + 1);
    }
}
