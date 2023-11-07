// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {Claims} from "../../contracts/Claims.sol";
import {IClaims} from "../../contracts/interfaces/IClaims.sol";
import {CurrencyLibrary, Currency} from "../../contracts/types/Currency.sol";
import {MockClaims} from "../../contracts/test/MockClaims.sol";

contract ClaimsTest is TokenFixture, Test {
    using CurrencyLibrary for Currency;

    MockClaims claimsImpl = new MockClaims();

    event Mint(address indexed to, uint256 indexed id, uint256 amount);
    event Burn(address indexed from, uint256 indexed id, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed id, uint256 amount);

    function setUp() public {}

    function testCanBurn(uint256 amount) public {
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        claimsImpl.mint(address(this), currency0, amount);

        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);
        vm.expectEmit(true, true, false, false);
        emit Burn(address(this), currency0.toId(), amount);
        claimsImpl.burn(currency0, amount);
    }

    function testCatchesUnderflowOnBurn(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        claimsImpl.mint(address(this), currency0, amount);

        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(abi.encodeWithSelector(IClaims.InsufficientBalance.selector));
        claimsImpl.burn(currency0, amount + 1);
    }

    function testCanTransfer(uint256 amount) public {
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        claimsImpl.mint(address(this), currency0, amount);

        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(this), address(1), currency0.toId(), amount);
        claimsImpl.transfer(address(1), currency0, amount);
    }

    function testCatchesUnderflowOnTransfer(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0.toId(), amount);
        claimsImpl.mint(address(this), currency0, amount);

        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);
        vm.expectRevert(abi.encodeWithSelector(IClaims.InsufficientBalance.selector));
        claimsImpl.transfer(address(1), currency0, amount + 1);
    }

    function testCatchesOverflowOnTransfer() public {
        claimsImpl.mint(address(0xdead), currency0, type(uint256).max);
        claimsImpl.mint(address(this), currency0, 1);
        // transfer will revert since overflow
        vm.expectRevert();
        claimsImpl.transfer(address(0xdead), currency0, 1);
    }
}
