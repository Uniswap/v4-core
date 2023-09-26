pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {ILockCallback} from "../../contracts/interfaces/callback/ILockCallback.sol";
import {LockDataLibrary} from "../../contracts/libraries/LockDataLibrary.sol";
import {LockData} from "../../contracts/types/LockData.sol";

contract LockDataLibraryTest is Test, Deployers, ILockCallback {
    PoolManager manager;

    function setUp() public {
        manager = Deployers.createFreshManager();
    }

    function testLockerLength() public {
        LockData dataDuringLockCallback = abi.decode(manager.lock(""), (LockData));
        assertEq(dataDuringLockCallback.length(), 1);
    }

    function lockAcquired(bytes calldata) public view returns (bytes memory) {
        LockData lockData = manager.getLockData();
        bytes memory data = abi.encode(lockData);
        return data;
    }
}
