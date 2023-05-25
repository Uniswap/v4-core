// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {PoolGetters} from "../../contracts/libraries/PoolGetters.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/libraries/CurrencyLibrary.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../../contracts/test/PoolLockTest.sol";
import {IERC20Minimal} from "../../contracts/interfaces/external/IERC20Minimal.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";

contract PoolGettersTest is Test, TokenFixture, Deployers, GasSnapshot {
    using PoolGetters for IPoolManager;

    Pool.State state;
    IPoolManager manager;
    PoolSwapTest swapRouter;

    PoolModifyPositionTest modifyPositionRouter;
    IPoolManager.PoolKey key;
    bytes32 poolId;

    address ADDRESS_ZERO = address(0);
    IHooks zeroHooks = IHooks(ADDRESS_ZERO);

    function setUp() public {
        (manager, key,) = Deployers.createFreshPool(zeroHooks, 3000, SQRT_RATIO_1_1);
        poolId = PoolId.toId(key);
        currency0 = key.currency0;
        currency1 = key.currency1;
        modifyPositionRouter = new PoolModifyPositionTest(manager);
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 10 ether);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(swapRouter), 10 ** 18);

        // populate pool storage data
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 5 ether));
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 1 ether, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );
    }

    function testGetPoolPrice() public {
        bytes32 _poolId = poolId;
        snapStart("poolGetSqrtPriceFromGetters");
        uint160 sqrtPriceX96Getter = manager.getPoolPrice(_poolId);
        snapEnd();

        snapStart("poolGetSqrtPriceFromSlot0");
        (uint160 sqrtPriceX96Slot0, , ) = manager.getSlot0(_poolId);
        snapEnd();

        assertEq(sqrtPriceX96Getter, sqrtPriceX96Slot0);
    }

    function testGetNetLiquidityAtTick() public {
        bytes32 _poolId = poolId;
        int128 netLiquidity = manager.getNetLiquidityAtTick(_poolId, 120);
        console.logInt(netLiquidity);
    }
}
