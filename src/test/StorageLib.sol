// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract StorageLib {
    function tstore(uint256 key, uint256 val) public {
        assembly {
            tstore(key, val)
        }
    }

    function tload(uint256 key) public view returns (uint256 val) {
        assembly {
            val := tload(key)
        }
        return val;
    }

    function sstore(uint256 key, uint256 val) public {
        assembly {
            sstore(key, val)
        }
    }

    function sload(uint256 key) public view returns (uint256 val) {
        assembly {
            val := sload(key)
        }
        return val;
    }
}
