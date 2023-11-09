pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {ILockCallback} from "../src/interfaces/callback/ILockCallback.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";

contract LockDataLibraryTest is Test, Deployers, ILockCallback {
    using CurrencyLibrary for Currency;

    PoolManager manager;
    PoolKey key;
    Currency currency0;

    function setUp() public {
        manager = Deployers.createFreshManager();
        (key,) = createAndInitPool(manager, IHooks(address(0)), 3000, SQRT_RATIO_1_1);
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency1)).mint(address(this), 1e18);

        PoolModifyPositionTest modifyRouter = new PoolModifyPositionTest(manager);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyRouter), 1e18);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(modifyRouter), 1e18);
        modifyRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-60, 60, 1000), "");
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
}
