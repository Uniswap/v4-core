// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "../../src/types/Currency.sol";

library SortTokens {
    function sort(MockERC20 tokenA, MockERC20 tokenB)
        internal
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
