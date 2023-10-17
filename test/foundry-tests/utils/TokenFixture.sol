// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UniMockERC20} from "./UniMockERC20.sol";
import {Currency} from "../../../contracts/types/Currency.sol";
import {SortTokens} from "./SortTokens.sol";

contract TokenFixture {
    Currency internal currency1;
    Currency internal currency0;

    function initializeTokens() internal {
        UniMockERC20 tokenA = new UniMockERC20("TestA", "A", 18, 1000 ether);
        UniMockERC20 tokenB = new UniMockERC20("TestB", "B", 18, 1000 ether);

        (currency0, currency1) = SortTokens.sort(tokenA, tokenB);
    }
}
