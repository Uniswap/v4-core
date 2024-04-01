// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {StorageLib} from "../src/test/StorageLib.sol";

contract TransientTest is Test, GasSnapshot {
    StorageLib storageLib;

    function setUp() public {
        storageLib = new StorageLib();
    }

    function test_gas_transient_set() public {
        snapStart("transient store");
        storageLib.tstore(1, 2);
        snapEnd();
    }

    function test_regular_gas_transient_set_warm() public {
        storageLib.tstore(1, 2);
        snapStart("transient store warm");
        storageLib.tstore(1, 3);
        snapEnd();
        assertEq(storageLib.tload(1), 3);
    }

    function _test_gas_transient_set_warm() public {
        storageLib.tstore(1, 2);
        snapStart("isolate transient store warm");
        storageLib.tstore(1, 3);
        snapEnd();
        assertEq(storageLib.tload(1), 3);
    }

    function test_isolate_gas_transient_set_warm() public {
        this._test_gas_transient_set_warm();
    }

    function test_gas_transient_get() public {
        snapStart("transient load");
        uint256 val = storageLib.tload(1);
        snapEnd();

        assertEq(val, 0);
    }

    function test_gas_storage_set() public {
        snapStart("storge store");
        storageLib.sstore(1, 2);
        snapEnd();
    }

    function test_gas_storage_set_warm() public {
        storageLib.sstore(1, 2);
        snapStart("storage store warm");
        storageLib.sstore(1, 3);
        snapEnd();
        assertEq(storageLib.sload(1), 3);
    }

    function test_gas_storage_get() public {
        snapStart("storage load");
        uint256 val = storageLib.sload(1);
        snapEnd();

        assertEq(val, 0);
    }
}
