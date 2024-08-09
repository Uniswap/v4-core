// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IActionsHarness {
    function routerCallback(bytes memory, bytes memory) external;
}