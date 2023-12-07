// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockERC6909Claims} from "../src/test/MockERC6909Claims.sol";

contract ERC6909ClaimsTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC6909Claims erc6909Claims;

    function setUp() public {
        (currency0, currency1) = deployMintAndApprove2Currencies();
        erc6909Claims = new MockERC6909Claims();
    }

    function test_burnFrom_withApproval(address sender, Currency currency, uint256 mintAmount, uint256 transferAmount)
        public
    {
        erc6909Claims.mint(sender, currency, mintAmount);
        uint256 id = currency.toId();

        vm.prank(sender);
        erc6909Claims.approve(address(this), id, mintAmount);

        if (transferAmount > mintAmount) {
            vm.expectRevert();
        }
        erc6909Claims.burnFrom(sender, currency, transferAmount);

        if (transferAmount <= mintAmount) {
            if (mintAmount == type(uint256).max) {
                assertEq(erc6909Claims.allowance(sender, address(this), id), type(uint256).max);
            } else {
                assertEq(erc6909Claims.allowance(sender, address(this), id), mintAmount - transferAmount);
            }
            assertEq(erc6909Claims.balanceOf(sender, id), mintAmount - transferAmount);
        }
    }
}
