// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import {Currency} from "../../../contracts/types/Currency.sol";

contract TokenFixture {
    Currency internal currency1;
    Currency internal currency0;

    function initializeTokens() internal {
        MockERC20 tokenA = new MockERC20("TestA", "A", 18);
        MockERC20 tokenB = new MockERC20("TestB", "B", 18);

        (currency0, currency1) = sortTokens(tokenA, tokenB);
    }

    function sortTokens(MockERC20 tokenA, MockERC20 tokenB)
        private
        pure
        returns (Currency _currency0, Currency _currency1)
    {
        if (address(tokenA) < address(tokenB)) {
            (_currency0, _currency1) = (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));
        } else {
            (_currency0, _currency1) = (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        }
    }
}
