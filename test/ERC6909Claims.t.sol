// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {MockERC6909Claims} from "../src/test/MockERC6909Claims.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract ERC6909ClaimsTest is Test, GasSnapshot {
    using CurrencyLibrary for Currency;

    MockERC6909Claims token;

    function setUp() public {
        token = new MockERC6909Claims();
    }

    function test_burnFrom_withApproval(address sender, uint256 id, uint256 mintAmount, uint256 transferAmount)
        public
    {
        token.mint(sender, id, mintAmount);

        vm.prank(sender);
        token.approve(address(this), id, mintAmount);

        if (transferAmount > mintAmount) {
            vm.expectRevert();
        }
        token.burnFrom(sender, id, transferAmount);

        if (transferAmount <= mintAmount) {
            if (mintAmount == type(uint256).max) {
                assertEq(token.allowance(sender, address(this), id), type(uint256).max);
            } else {
                if (sender != address(this)) {
                    assertEq(token.allowance(sender, address(this), id), mintAmount - transferAmount);
                } else {
                    assertEq(token.allowance(sender, address(this), id), mintAmount);
                }
            }
            assertEq(token.balanceOf(sender, id), mintAmount - transferAmount);
        }
    }

    function test_burnFrom_revertsWithNoApproval() public {
        token.mint(address(this), 1337, 100);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.burnFrom(address(this), 1337, 100);
    }
}
