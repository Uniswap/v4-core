// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockV46909} from "../src/test/MockV46909.sol";

contract V46909Test is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockV46909 v46909;

    function setUp() public {
        (currency0, currency1) = deployMintAndApprove2Currencies();
        v46909 = new MockV46909();
    }

    function testBurnFromFromWithApproval(address sender, Currency currency, uint256 mintAmount, uint256 transferAmount)
        public
    {
        v46909.mint(sender, currency, mintAmount);
        uint256 id = currency.toId();

        vm.prank(sender);
        v46909.approve(address(this), id, mintAmount);

        if (transferAmount > mintAmount) {
            vm.expectRevert();
        }
        v46909.burnFrom(sender, id, transferAmount);

        if (transferAmount <= mintAmount) {
            if (mintAmount == type(uint256).max) {
                assertEq(v46909.allowance(sender, address(this), id), type(uint256).max);
            } else {
                assertEq(v46909.allowance(sender, address(this), id), mintAmount - transferAmount);
            }
            assertEq(v46909.balanceOf(sender, id), mintAmount - transferAmount);
        }
    }
}
