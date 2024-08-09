// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "src/types/Currency.sol";

interface IActor{
    function proxyApprove(Currency token, address spender) external;
}