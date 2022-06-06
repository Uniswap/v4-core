pragma solidity ^0.8.13;

import {Test} from '../../lib/Test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Hooks} from '../../contracts/libraries/Hooks.sol';
import {MockHooks} from '../../contracts/test/MockHooks.sol';
import {IPoolManager} from '../../contracts/interfaces/IPoolManager.sol';
import {TestERC20} from '../../contracts/test/TestERC20.sol';
import {IHooks} from '../../contracts/interfaces/IHooks.sol';
import {IERC20Minimal} from '../../contracts/interfaces/external/IERC20Minimal.sol';
import {PoolManager} from '../../contracts/PoolManager.sol';
import {Deployers} from './utils/Deployers.sol';

contract HooksTest is DSTest {
    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);
    }

    function testStuff() public {
        uint256 a = 6;
        assertEq(a, 1);
    }

    function testInitializeSucceedsWithHook() public {
        (PoolManager manager, IPoolManager.PoolKey memory key) = Deployers.createFreshPool(mockHooks, 1);
        (uint160 sqrtPriceX96,) = manager.getSlot0(key); 
        assertEq(sqrtPriceX96, 1);
    }

    function testBeforeInitializeInvalidReturn() public {
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 1);
    }

    function testAfterInitializeInvalidReturn() public {
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 1);
    }

    //function testSafeBeforeModifyPosition() public {
        //Hooks.safeBeforeModifyPosition(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.ModifyPositionParams(1, 1, 1)
        //);
    //}

    //function testFailSafeBeforeModifyPositionInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));

        //Hooks.safeBeforeModifyPosition(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.ModifyPositionParams(1, 1, 1)
        //);
    //}

    //function testSafeAfterModifyPosition() public {
        //Hooks.safeAfterModifyPosition(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.ModifyPositionParams(1, 1, 1),
            //IPoolManager.BalanceDelta(1, 1)
        //);
    //}

    //function testFailSafeAfterModifyPositionInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));

        //Hooks.safeAfterModifyPosition(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.ModifyPositionParams(1, 1, 1),
            //IPoolManager.BalanceDelta(1, 1)
        //);
    //}

    //function testSafeBeforeSwap() public {
        //Hooks.safeBeforeSwap(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.SwapParams(true, 1, 1)
        //);
    //}

    //function testFailSafeBeforeSwapInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));

        //Hooks.safeBeforeSwap(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.SwapParams(true, 1, 1)
        //);
    //}

    //function testSafeAfterSwap() public {
        //Hooks.safeAfterSwap(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.SwapParams(true, 1, 1),
            //IPoolManager.BalanceDelta(1, 1)
        //);
    //}

    //function testFailSafeAfterSwapInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        //Hooks.safeAfterSwap(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //IPoolManager.SwapParams(true, 1, 1),
            //IPoolManager.BalanceDelta(1, 1)
        //);
    //}

    //function testSafeBeforeDonate() public {
        //Hooks.safeBeforeDonate(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //1,
            //1
        //);
    //}

    //function testFailSafeBeforeDonateSwapInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));

        //Hooks.safeBeforeDonate(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //1,
            //1
        //);
    //}

    //function testSafeAfterDonate() public {
        //Hooks.safeAfterDonate(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //1,
            //1
        //);
    //}

    //function testFailSafeAfterDonateSwapInvalidReturn() public {
        //mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        //Hooks.safeAfterDonate(
            //IHooks(mockHooks),
            //address(this),
            //IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            //1,
            //1
        //);
    //}
}
