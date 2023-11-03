pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {ILockCallback} from "../../contracts/interfaces/callback/ILockCallback.sol";
import {LockData, LockDataLibrary} from "../../contracts/types/LockData.sol";

contract LockDataLibraryTest is Test, Deployers, ILockCallback {
    PoolManager manager;

    function setUp() public {
        manager = Deployers.createFreshManager();
    }

    function testLockerLength() public {
        uint256 lengthDuringLockCallback = abi.decode(manager.lock(""), (uint256));
        assertEq(lengthDuringLockCallback, 1);
    }

    function lockAcquired(bytes calldata) public view returns (bytes memory) {
        // todo how should we expose this with the new library
        uint256 len = manager.getLockLength();
        bytes memory data = abi.encode(len);
        return data;
    }
}
