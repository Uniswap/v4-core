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
import {Lockers} from "../src/libraries/Lockers.sol";

contract LockersLibrary is Test, Deployers, ILockCallback {
    using CurrencyLibrary for Currency;

    uint256 constant LOCKERS_OFFSET = uint256(1);

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    function testLockerLengthAndNonzeroDeltaCount() public {
        (uint256 lengthDuringLockCallback, uint256 nonzeroDeltaCountDuringCallback) =
            abi.decode(manager.lock(""), (uint256, uint256));
        assertEq(lengthDuringLockCallback, 1);
        assertEq(nonzeroDeltaCountDuringCallback, 1);
        assertEq(manager.getLockLength(), 0);
        assertEq(manager.getLockNonzeroDeltaCount(), 0);
    }

    function lockAcquired(bytes calldata) public returns (bytes memory) {
        uint256 len = manager.getLockLength();

        // apply a delta and save count
        manager.take(key.currency0, address(this), 1);
        uint256 count = manager.getLockNonzeroDeltaCount();
        key.currency0.transfer(address(manager), 1);
        manager.settle(key.currency0);

        bytes memory data = abi.encode(len, count);
        return data;
    }

    function test_push() public {
        Lockers.push(address(this));
        assertEq(Lockers.length(), 1);
        assertEq(Lockers.getLocker(LOCKERS_OFFSET), address(this));
    }

    function test_push_multipleAddressesFuzz(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            assertEq(Lockers.length(), i);
            Lockers.push(addr);
            assertEq(Lockers.length(), LOCKERS_OFFSET + i);
            assertEq(Lockers.getLocker(LOCKERS_OFFSET + i), addr);
        }
    }

    function test_getCurrentLocker_multipleAddressesFuzz(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            assertEq(Lockers.length(), i);
            Lockers.push(addr);
            assertEq(Lockers.length(), LOCKERS_OFFSET + i);
            assertEq(Lockers.getCurrentLocker(), addr);
        }
    }

    function test_pop() public {
        Lockers.push(address(this));
        assertEq(Lockers.length(), 1);
        Lockers.pop();
        assertEq(Lockers.length(), 0);
    }

    function test_pop_multipleAddressesFuzz(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            Lockers.push(addr);
        }

        assertEq(Lockers.length(), addrs.length);

        for (uint256 i = 0; i < addrs.length; i++) {
            Lockers.pop();
            assertEq(Lockers.length(), addrs.length - i - LOCKERS_OFFSET);
        }

        assertEq(Lockers.length(), 0);
    }

    function test_clear(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            address addr = addrs[i];
            Lockers.push(addr);
        }

        assertEq(Lockers.length(), addrs.length);
        Lockers.clear();
        assertEq(Lockers.length(), 0);
    }

    function test_incrementNonzeroDeltaCount() public {
        Lockers.incrementNonzeroDeltaCount();
        assertEq(Lockers.nonzeroDeltaCount(), 1);
    }

    function test_incrementNonzeroDeltaCountFuzz(uint8 count) public {
        for (uint256 i = 0; i < count; i++) {
            Lockers.incrementNonzeroDeltaCount();
            assertEq(Lockers.nonzeroDeltaCount(), i + 1);
        }
    }

    function test_decrementNonzeroDeltaCount() public {
        Lockers.incrementNonzeroDeltaCount();
        Lockers.decrementNonzeroDeltaCount();
        assertEq(Lockers.nonzeroDeltaCount(), 0);
    }

    function test_decrementNonzeroDeltaCountFuzz(uint8 count) public {
        for (uint256 i = 0; i < count; i++) {
            Lockers.incrementNonzeroDeltaCount();
        }

        assertEq(Lockers.nonzeroDeltaCount(), count);

        for (uint256 i = 0; i < count; i++) {
            Lockers.decrementNonzeroDeltaCount();
            assertEq(Lockers.nonzeroDeltaCount(), count - i - 1);
        }
    }
}
