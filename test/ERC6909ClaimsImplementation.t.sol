// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {ERC6909ClaimsImplementation} from "../src/test/ERC6909ClaimsImplementation.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract ERC6909ClaimsTest is Test, GasSnapshot {
    using CurrencyLibrary for Currency;

    ERC6909ClaimsImplementation token;

    function setUp() public {
        token = new ERC6909ClaimsImplementation();
    }

    function test_burnFrom_withApproval(address sender, uint256 id, uint256 mintAmount, uint256 burnAmount)
        public
    {
        token.mint(sender, id, mintAmount);

        vm.prank(sender);
        token.approve(address(this), id, mintAmount);

        if (burnAmount > mintAmount) {
            vm.expectRevert();
        }
        token.burnFrom(sender, id, burnAmount);

        if (burnAmount <= mintAmount) {
            if (mintAmount == type(uint256).max) {
                assertEq(token.allowance(sender, address(this), id), type(uint256).max);
            } else {
                if (sender != address(this)) {
                    assertEq(token.allowance(sender, address(this), id), mintAmount - burnAmount);
                } else {
                    assertEq(token.allowance(sender, address(this), id), mintAmount);
                }
            }
            assertEq(token.balanceOf(sender, id), mintAmount - burnAmount);
        }
    }

    function test_burnFrom_withOperator(address sender, uint256 id, uint256 mintAmount, uint256 burnAmount)
        public
    {
        token.mint(sender, id, mintAmount);

        vm.prank(sender);
        token.setOperator(address(this), true);

        if (burnAmount > mintAmount) {
            vm.expectRevert();
        }
        token.burnFrom(sender, id, burnAmount);

        if (burnAmount <= mintAmount) {
            assertEq(token.balanceOf(sender, id), mintAmount - burnAmount);
        }
        assertEq(token.allowance(sender, address(this), id), 0);
    }

    function test_burnFrom_revertsWithNoApproval() public {
        token.mint(address(this), 1337, 100);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.burnFrom(address(this), 1337, 100);
    }
}
