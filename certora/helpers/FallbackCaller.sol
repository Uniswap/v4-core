// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FallbackCaller {
    function callFallback(address to, uint256 amount) external payable {
        require(msg.value == amount, "must transfer native amount");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Native Transfer Failed");
    }
}
