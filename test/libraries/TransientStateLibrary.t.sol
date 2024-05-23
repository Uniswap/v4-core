// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "../../src/types/Currency.sol";
import {CurrencyDelta} from "../../src/libraries/CurrencyDelta.sol";
import {Deployers} from "../utils/Deployers.sol";
import {Position} from "../../src/libraries/Position.sol";
import {Reserves} from "../../src/libraries/Reserves.sol";
import {Lock} from "../../src/libraries/Lock.sol";
import {NonZeroDeltaCount} from "../../src/libraries/NonZeroDeltaCount.sol";
import {TransientStateLibrary} from "../../src/libraries/TransientStateLibrary.sol";
import {Fuzzers} from "../../src/test/Fuzzers.sol";
import {Exttload} from "../../src/Exttload.sol";

contract TransientStateLibraryTest is Test, Deployers, Fuzzers, GasSnapshot, Exttload {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Reserves for Currency;
    using CurrencyDelta for Currency;

    /*
     * @dev The wrapper contract is used to prevent transient storage from being cleared
     * when tests are run in --isolate test mode by ensuring all operations are performed within a single transaction.
     */
    TransientStateLibraryTest wrapper;
    IPoolManager self = IPoolManager(address(this));
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0x0)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Wrap the contract to test in a single transaction
        address payable selfPayable = payable(address(this));
        wrapper = TransientStateLibraryTest(selfPayable);
    }

    function test_getReserves() public {
        // Act
        uint256 reserves0 = TransientStateLibrary.getReserves(manager, currency0);
        uint256 reserves1 = TransientStateLibrary.getReserves(manager, currency1);

        // Assert
        assertEq(reserves0, 0);
        assertEq(reserves1, 0);
    }

    // Wrapper function to test in a single transaction
    function test_getReserves_withSync() public {
        wrapper._test_getReserves_withSync();
    }

    function _test_getReserves_withSync() public {
        // Arrange
        manager.sync(currency0);
        manager.sync(currency1);

        // Act
        uint256 reserves0 = TransientStateLibrary.getReserves(manager, currency0);
        uint256 reserves1 = TransientStateLibrary.getReserves(manager, currency1);

        // Assert
        assertEq(reserves0, type(uint256).max); // See Reserves.sol line 9
        assertEq(reserves1, type(uint256).max); // See Reserves.sol line 9
    }

    // Wrapper function to test in a single transaction.
    function test_getReserves_withTransferAndSync() public {
        wrapper._test_getReserves_withTransferAndSync();
    }

    function _test_getReserves_withTransferAndSync() public {
        // Arrange
        uint256 amount0 = 10 ether;
        uint256 amount1 = 20 ether;
        currency0.transfer(address(manager), amount0);
        currency1.transfer(address(manager), amount1);
        manager.sync(currency0);
        manager.sync(currency1);

        // Act
        uint256 reserves0 = TransientStateLibrary.getReserves(manager, currency0);
        uint256 reserves1 = TransientStateLibrary.getReserves(manager, currency1);

        // Assert
        assertEq(reserves0, amount0);
        assertEq(reserves1, amount1);
    }

    function test_getReserves_self() public {
        // Arrange
        uint256 amount0 = 10 ether;
        uint256 amount1 = 20 ether;
        currency0.setReserves(amount0);
        currency1.setReserves(amount1);

        // Act
        uint256 reserves0 = TransientStateLibrary.getReserves(self, currency0);
        uint256 reserves1 = TransientStateLibrary.getReserves(self, currency1);

        // Assert
        assertEq(reserves0, amount0);
        assertEq(reserves1, amount1);
    }

    // Wrapper function to test in a single transaction
    function test_fuzz_getReserves(uint256 amount0, uint256 amount1) public {
        wrapper._test_fuzz_getReserves(amount0, amount1);
    }

    function _test_fuzz_getReserves(uint256 amount0, uint256 amount1) public {
        // Arrange
        vm.assume(amount0 <= currency0.balanceOfSelf() && amount0 != 0);
        vm.assume(amount1 <= currency1.balanceOfSelf() && amount1 != 0);

        currency0.transfer(address(manager), amount0);
        currency1.transfer(address(manager), amount1);
        manager.sync(currency0);
        manager.sync(currency1);

        // Act
        uint256 reserves0 = TransientStateLibrary.getReserves(manager, currency0);
        uint256 reserves1 = TransientStateLibrary.getReserves(manager, currency1);

        // Assert
        assertEq(reserves0, amount0);
        assertEq(reserves1, amount1);
    }

    /// @notice Additional tests using the manager can be found in src/test/Pool~~Test.sol
    function test_getNonzeroDeltaCount() public {
        // Act
        uint256 count = TransientStateLibrary.getNonzeroDeltaCount(manager);

        // Assert
        assertEq(count, 0);
    }

    function test_getNonzeroDeltaCount_self() public {
        // Arrange
        NonZeroDeltaCount.increment();

        // Act
        uint256 queriedCount = TransientStateLibrary.getNonzeroDeltaCount(self);

        // Assert
        assertEq(queriedCount, 1);
    }

    function test_fuzz_getNonzeroDeltaCount_self(uint8 incrementCount, uint8 decrementCount) public {
        // Arrange
        vm.assume(incrementCount > decrementCount);
        for (uint8 i = 0; i < incrementCount; i++) {
            NonZeroDeltaCount.increment();
        }
        for (uint8 i = 0; i < decrementCount; i++) {
            NonZeroDeltaCount.decrement();
        }

        // Act
        uint256 queriedCount = TransientStateLibrary.getNonzeroDeltaCount(self);

        // Assert
        assertEq(queriedCount, incrementCount - decrementCount);
    }

    /// @notice Additional tests using the manager can be found in src/test/Pool~~Test.sol
    function test_currencyDelta() public {
        // Act
        int256 delta0 = TransientStateLibrary.currencyDelta(manager, address(1), currency0);
        int256 delta1 = TransientStateLibrary.currencyDelta(manager, address(1), currency1);

        // Assert
        assertEq(delta0, 0, "delta0 should be 0");
        assertEq(delta1, 0, "delta1 should be 0");
    }

    function test_currencyDelta_self() public {
        // Arrange
        currency0.setDelta(address(1), 10 ether);
        currency1.setDelta(address(1), 20 ether);

        // Act
        int256 delta0 = TransientStateLibrary.currencyDelta(self, address(1), currency0);
        int256 delta1 = TransientStateLibrary.currencyDelta(self, address(1), currency1);

        // Assert
        assertEq(delta0, 10 ether);
        assertEq(delta1, 20 ether);
    }

    function test_fuzz_currencyDelta(int256 inputDelta0, int256 inputDelta1) public {
        // Arrange
        currency0.setDelta(address(1), inputDelta0);
        currency1.setDelta(address(1), inputDelta1);

        // Act
        int256 queriedDelta0 = TransientStateLibrary.currencyDelta(self, address(1), currency0);
        int256 queriedDelta1 = TransientStateLibrary.currencyDelta(self, address(1), currency1);

        // Assert
        assertEq(queriedDelta0, inputDelta0);
        assertEq(queriedDelta1, inputDelta1);
    }

    /// @notice Additional tests using the manager can be found in src/test/Pool~~Test.sol
    function test_isUnlocked() public {
        // Act
        bool unlocked = TransientStateLibrary.isUnlocked(manager);

        // Assert
        assertFalse(unlocked, "should not be unlocked");
    }

    function test_isUnlocked_self() public {
        // Arrange
        Lock.unlock();

        // Act
        bool unlocked = TransientStateLibrary.isUnlocked(self);

        // Assert
        assertTrue(unlocked, "should be unlocked");
    }
}
