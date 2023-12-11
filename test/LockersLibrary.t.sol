pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {ILockCallback} from "../src/interfaces/callback/ILockCallback.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Locker} from "../src/libraries/Locker.sol";

contract LockersLibraryTest is Test, Deployers, ILockCallback {
    using CurrencyLibrary for Currency;

    uint256 constant LOCKERS_OFFSET = uint256(1);

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    function testLockerLengthAndNonzeroDeltaCount() public {
        (uint256 nonzeroDeltaCountDuringCallback) = abi.decode(manager.lock(address(this), ""), (uint256));
        assertEq(nonzeroDeltaCountDuringCallback, 1);
        assertEq(manager.getLockNonzeroDeltaCount(), 0);
    }

    function lockAcquired(address, bytes calldata) public returns (bytes memory) {
        // apply a delta and save count
        manager.take(key.currency0, address(this), 1);
        uint256 count = manager.getLockNonzeroDeltaCount();
        key.currency0.transfer(address(manager), 1);
        manager.settle(key.currency0);

        bytes memory data = abi.encode(count);
        return data;
    }

    function test_incrementNonzeroDeltaCount() public {
        Locker.incrementNonzeroDeltaCount();
        assertEq(Locker.nonzeroDeltaCount(), 1);
    }

    function test_incrementNonzeroDeltaCountFuzz(uint8 count) public {
        for (uint256 i = 0; i < count; i++) {
            Locker.incrementNonzeroDeltaCount();
            assertEq(Locker.nonzeroDeltaCount(), i + 1);
        }
    }

    function test_decrementNonzeroDeltaCount() public {
        Locker.incrementNonzeroDeltaCount();
        Locker.decrementNonzeroDeltaCount();
        assertEq(Locker.nonzeroDeltaCount(), 0);
    }

    function test_decrementNonzeroDeltaCountFuzz(uint8 count) public {
        for (uint256 i = 0; i < count; i++) {
            Locker.incrementNonzeroDeltaCount();
        }

        assertEq(Locker.nonzeroDeltaCount(), count);

        for (uint256 i = 0; i < count; i++) {
            Locker.decrementNonzeroDeltaCount();
            assertEq(Locker.nonzeroDeltaCount(), count - i - 1);
        }
    }
}
