// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract EmptyRevertContract {
    // a contract to simulate reverting with no returndata, to test that our error catching works
    fallback() external {
        revert();
    }
}
