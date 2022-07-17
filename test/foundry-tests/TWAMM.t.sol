pragma solidity ^0.8.15;

import {Test} from 'forge-std/Test.sol';
import {Vm} from 'forge-std/Vm.sol';
import {IPoolManager} from '../../contracts/interfaces/IPoolManager.sol';
import {TestERC20} from '../../contracts/test/TestERC20.sol';
import {IERC20Minimal} from '../../contracts/interfaces/external/IERC20Minimal.sol';
import {TWAMMHook} from '../../contracts/hooks/TWAMMHook.sol';
import {TWAMM} from '../../contracts/libraries/TWAMM/TWAMM.sol';
import {Hooks} from '../../contracts/libraries/Hooks.sol';
import {TickMath} from '../../contracts/libraries/TickMath.sol';
import {PoolManager} from '../../contracts/PoolManager.sol';
import {PoolModifyPositionTest} from '../../contracts/test/PoolModifyPositionTest.sol';
import {PoolSwapTest} from '../../contracts/test/PoolSwapTest.sol';
import {PoolDonateTest} from '../../contracts/test/PoolDonateTest.sol';
import {Deployers} from './utils/Deployers.sol';

contract HooksTest is Test, Deployers {
    TWAMMHook twamm;
    PoolManager manager;
    IPoolManager.PoolKey poolKey;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;
    bytes32 id;
    address hookAddress;


    function setUp() public {
        manager = new PoolManager(500000);
        vm.prank(0xdEAa3dcb5f54455280F71083a3dA24692F197F13); // address to deploy TWAMM with correct hook address
        twamm = new TWAMMHook(manager, 10_000);
        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));
        (poolKey, id) = createPool(manager, twamm, SQRT_RATIO_1_1);
        poolKey.token0.approve(address(modifyPositionRouter), 100 ether);
        poolKey.token1.approve(address(modifyPositionRouter), 100 ether);
        TestERC20(address(poolKey.token0)).mint(address(this), 100 ether);
        TestERC20(address(poolKey.token1)).mint(address(this), 100 ether);
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether));
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether));
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(TickMath.MIN_TICK, TickMath.MAX_TICK, 10 ether));
    }

    function testTWAMMbeforeInitializeInitializesTWAMM() public {
        (IPoolManager.PoolKey memory initKey, bytes32 initId) = newPoolKey(twamm);
        assertEq(twamm.lastVirtualOrderTimestamp(initId), 0);
        vm.warp(10000);
        manager.initialize(initKey, SQRT_RATIO_1_1);
        assertEq(twamm.lastVirtualOrderTimestamp(initId), 10000);
    }

    function testTWAMMSubmitLTOStoresOrderUnderCorrectPool() public {
        TWAMM.OrderKey memory orderKey = TWAMM.OrderKey(address(this), 30000, true);

        TWAMM.Order memory nullOrder = twamm.getOrder(poolKey, orderKey);
        assertEq(nullOrder.sellRate, 0);
        assertEq(nullOrder.earningsFactorLast, 0);

        poolKey.token0.approve(address(twamm), 100 ether);
        vm.warp(10000);
        twamm.submitLongTermOrder(poolKey, orderKey, 1 ether);

        TWAMM.Order memory submittedOrder = twamm.getOrder(poolKey, orderKey);
        assertEq(submittedOrder.sellRate, 1 ether / 20000);
        assertEq(submittedOrder.earningsFactorLast, 0);
    }

    function testTWAMMOrderStoresEarningsFactorLast() public {
        TWAMM.OrderKey memory orderKey1 = TWAMM.OrderKey(address(this), 30000, true);
        TWAMM.OrderKey memory orderKey2 = TWAMM.OrderKey(address(this), 40000, true);
        TWAMM.OrderKey memory orderKey3 = TWAMM.OrderKey(address(this), 40000, false);

        poolKey.token0.approve(address(twamm), 100e18);
        poolKey.token1.approve(address(twamm), 100e18);
        vm.warp(10000);
        twamm.submitLongTermOrder(poolKey, orderKey1, 1e18);
        twamm.submitLongTermOrder(poolKey, orderKey3, 10e18);
        vm.warp(30000);
        poolKey.token0.approve(address(twamm), 100e18);
        twamm.submitLongTermOrder(poolKey, orderKey2, 1e18);
        vm.warp(40000);

        TWAMM.Order memory submittedOrder = twamm.getOrder(poolKey, orderKey2);
        (, uint256 earningsFactorCurrent) = twamm.getOrderPool(poolKey, true);
        assertEq(submittedOrder.sellRate, 1 ether / 10000);
        assertEq(submittedOrder.earningsFactorLast, earningsFactorCurrent);
    }

    function testTWAMMEndToEndSimEvenTrading() public {
        uint256 orderAmount = 1e18;
        TWAMM.OrderKey memory orderKey1 = TWAMM.OrderKey(address(this), 30000, true);
        TWAMM.OrderKey memory orderKey2 = TWAMM.OrderKey(address(this), 30000, false);

        poolKey.token0.approve(address(twamm), 100e18);
        poolKey.token1.approve(address(twamm), 100e18);
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-2000, 2000, 10 ether));

        vm.warp(10000);
        twamm.submitLongTermOrder(poolKey, orderKey1, orderAmount);
        twamm.submitLongTermOrder(poolKey, orderKey2, orderAmount);
        vm.warp(20000);
        twamm.executeTWAMMOrders(poolKey);
        twamm.updateLongTermOrder(poolKey, orderKey1, 0);
        twamm.updateLongTermOrder(poolKey, orderKey2, 0);

        uint256 earningsToken0 = twamm.tokensOwed(address(poolKey.token0), address(this));
        uint256 earningsToken1 = twamm.tokensOwed(address(poolKey.token1), address(this));

        assertEq(earningsToken0, orderAmount/2);
        assertEq(earningsToken1, orderAmount/2);

        uint256 balance0BeforeTWAMM = poolKey.token0.balanceOf(address(twamm));
        uint256 balance1BeforeTWAMM = poolKey.token1.balanceOf(address(twamm));
        uint256 balance0BeforeThis = poolKey.token0.balanceOf(address(this));
        uint256 balance1BeforeThis = poolKey.token1.balanceOf(address(this));

        vm.warp(30000);
        twamm.executeTWAMMOrders(poolKey);
        twamm.updateLongTermOrder(poolKey, orderKey1, 0);
        twamm.updateLongTermOrder(poolKey, orderKey2, 0);
        twamm.claimTokens(poolKey.token0, address(this), 0);
        twamm.claimTokens(poolKey.token1, address(this), 0);

        uint256 balance0AfterTWAMM = poolKey.token0.balanceOf(address(twamm));
        uint256 balance1AfterTWAMM = poolKey.token1.balanceOf(address(twamm));
        uint256 balance0AfterThis = poolKey.token0.balanceOf(address(this));
        uint256 balance1AfterThis = poolKey.token1.balanceOf(address(this));

        assertEq(balance1AfterTWAMM, 0);
        assertEq(balance0AfterTWAMM, 0);
        assertEq(balance0BeforeTWAMM - balance0AfterTWAMM, orderAmount);
        assertEq(balance0AfterThis - balance0BeforeThis, orderAmount);
        assertEq(balance1BeforeTWAMM - balance1AfterTWAMM, orderAmount);
        assertEq(balance1AfterThis - balance1BeforeThis, orderAmount);
    }
}
