// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";

contract PoolIdTest is Test {
    function test_fuzz_toId(PoolKey memory poolKey) public pure {
        bytes memory encodedKey = abi.encode(poolKey);
        bytes32 expectedHash = keccak256(encodedKey);
        assertEq(PoolId.unwrap(poolKey.toId()), expectedHash, "hashes not equal");
    }
}
