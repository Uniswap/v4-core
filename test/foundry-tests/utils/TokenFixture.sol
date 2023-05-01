// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import {Currency} from "../../../contracts/libraries/CurrencyLibrary.sol";

contract TokenFixture {
    Currency public currency0;
    Currency public currency1;
    MockERC20 public token2;

    function initializeTokens() public {
        MockERC20 tokenA = new MockERC20("TestA", "A", 18);
        MockERC20 tokenB = new MockERC20("TestB", "B", 18);
        MockERC20 token2 = new MockERC20("TestC", "C", 18);

        (currency0, currency1) = sortTokens(tokenA, tokenB);
    }

    function sortTokens(MockERC20 tokenA, MockERC20 tokenB) internal returns (Currency currency0, Currency currency1) {
        if (address(tokenA) < address(tokenB)) {
            (currency0, currency1) = (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));
        } else {
            (currency0, currency1) = (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        }
    }
}