// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

type TransientStorageProxy is address;

library TransientStorage {
    function init() internal returns (TransientStorageProxy proxy) {
        // initCode == bytecode from `yarn compile-tsp`
        bytes
            memory initCode = hex'602980600d600039806000f3fe366020811460135760408114602057600080fd5b600035b360005260206000f35b602035600035b450';
        assembly {
            let size := mload(initCode)
            proxy := create2(0, add(initCode, 32), size, 0)
        }
    }

    function load(TransientStorageProxy proxy, uint256 slot) internal returns (uint256 value) {
        assembly {
            mstore(0, slot)
            if iszero(delegatecall(gas(), proxy, 0, 32, 0, 32)) {
                revert(0, 0)
            }
            value := mload(0)
        }
    }

    function store(
        TransientStorageProxy proxy,
        uint256 slot,
        uint256 value
    ) internal {
        assembly {
            mstore(0, slot)
            mstore(32, value)
            if iszero(delegatecall(gas(), proxy, 0, 32, 0, 32)) {
                revert(0, 0)
            }
        }
    }
}
