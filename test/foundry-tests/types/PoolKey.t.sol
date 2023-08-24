// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PoolId, PoolIdLibrary, PoolKey} from "../../../contracts/types/PoolId.sol";

contract TestPoolKey is Test {
    using PoolIdLibrary for PoolKey;
    
    function testPoolIdCreation(PoolKey memory poolKey) public {
        assertEq(keccak256(abi.encode(poolKey)), PoolId.unwrap(poolKey.toId()));
    }
}
