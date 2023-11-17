// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Claims} from "../src/Claims.sol";
import {IClaims} from "../src/interfaces/IClaims.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {MockClaims} from "../src/test/MockClaims.sol";
import {Deployers} from "./utils/Deployers.sol";

contract ClaimsTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockClaims claimsImpl = new MockClaims();

    event Mint(address indexed to, Currency indexed currency, uint256 amount);
    event Burn(address indexed from, Currency indexed currency, uint256 amount);
    event Transfer(address indexed from, address indexed to, Currency indexed currency, uint256 amount);

    function setUp() public {
        (currency0, currency1) = deployMintAndApprove2Currencies();
    }

    function testCanBurn(uint256 amount) public {
        assertEq(claimsImpl.balanceOf(address(this), currency0), 0);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0, amount);
        claimsImpl.mint(address(this), currency0, amount);
        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);

        vm.expectEmit(true, true, false, false);
        emit Burn(address(this), currency0, amount);
        claimsImpl.burn(currency0, amount);
        assertEq(claimsImpl.balanceOf(address(this), currency0), 0);
    }

    function testCatchesUnderflowOnBurn(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0, amount);
        claimsImpl.mint(address(this), currency0, amount);
        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);

        vm.expectRevert(abi.encodeWithSelector(IClaims.InsufficientBalance.selector));
        claimsImpl.burn(currency0, amount + 1);
    }

    function testCanTransfer(uint256 amount) public {
        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0, amount);
        claimsImpl.mint(address(this), currency0, amount);
        assertEq(claimsImpl.balanceOf(address(this), currency0), amount);

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(this), address(1), currency0, amount);
        claimsImpl.transfer(address(1), currency0, amount);
        assertEq(claimsImpl.balanceOf(address(this), currency0), 0);
        assertEq(claimsImpl.balanceOf(address(1), currency0), amount);
    }

    function testCatchesUnderflowOnTransfer(uint256 amount) public {
        vm.assume(amount < type(uint256).max - 1);

        vm.expectEmit(true, true, false, false);
        emit Mint(address(this), currency0, amount);
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

    function testCanTransferToZeroAddress() public {
        claimsImpl.mint(address(this), currency0, 1);
        assertEq(claimsImpl.balanceOf(address(this), currency0), 1);
        assertEq(claimsImpl.balanceOf(address(0), currency0), 0);

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(this), address(0), currency0, 1);
        claimsImpl.transfer(address(0), currency0, 1);

        assertEq(claimsImpl.balanceOf(address(this), currency0), 0);
        assertEq(claimsImpl.balanceOf(address(0), currency0), 1);
    }

    function testTransferToClaimsContractFails() public {
        claimsImpl.mint(address(this), currency0, 1);
        vm.expectRevert(abi.encodeWithSelector(IClaims.InvalidAddress.selector));
        claimsImpl.transfer(address(claimsImpl), currency0, 1);
    }
}
