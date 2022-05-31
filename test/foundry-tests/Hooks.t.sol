pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Hooks} from '../../contracts/libraries/Hooks.sol';
import {MockHooks} from '../../contracts/test/TestHooksImpl.sol';
import {IPoolManager} from '../../contracts/interfaces/IPoolManager.sol';
import {IHooks} from '../../contracts/interfaces/IHooks.sol';
import {IERC20Minimal} from '../../contracts/interfaces/external/IERC20Minimal.sol';

contract HooksTest is DSTest {
    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    MockHooks mockHooks;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);
    }

    function testSafeBeforeInitialize() public {
        Hooks.safeBeforeInitialize(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1
        );
    }

    function testFailSafeBeforeInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));

        Hooks.safeBeforeInitialize(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1
        );
    }

    function testSafeAfterInitialize() public {
        Hooks.safeAfterInitialize(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }

    function testFailSafeAfterInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));

        Hooks.safeAfterInitialize(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }

    function testSafeBeforeModifyPosition() public {
        Hooks.safeBeforeModifyPosition(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.ModifyPositionParams(1, 1, 1)
        );
    }

    function testFailSafeBeforeModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));

        Hooks.safeBeforeModifyPosition(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.ModifyPositionParams(1, 1, 1)
        );
    }

    function testSafeAfterModifyPosition() public {
        Hooks.safeAfterModifyPosition(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.ModifyPositionParams(1, 1, 1),
            IPoolManager.BalanceDelta(1, 1)
        );
    }

    function testFailSafeAfterModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));

        Hooks.safeAfterModifyPosition(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.ModifyPositionParams(1, 1, 1),
            IPoolManager.BalanceDelta(1, 1)
        );
    }

    function testSafeBeforeSwap() public {
        Hooks.safeBeforeSwap(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.SwapParams(true, 1, 1)
        );
    }

    function testFailSafeBeforeSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));

        Hooks.safeBeforeSwap(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.SwapParams(true, 1, 1)
        );
    }

    function testSafeAfterSwap() public {
        Hooks.safeAfterSwap(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.SwapParams(true, 1, 1),
            IPoolManager.BalanceDelta(1, 1)
        );
    }

    function testFailSafeAfterSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));

        Hooks.safeAfterSwap(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            IPoolManager.SwapParams(true, 1, 1),
            IPoolManager.BalanceDelta(1, 1)
        );
    }

    function testSafeBeforeDonate() public {
        Hooks.safeBeforeDonate(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }

    function testFailSafeBeforeDonateSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));

        Hooks.safeBeforeDonate(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }

    function testSafeAfterDonate() public {
        Hooks.safeAfterDonate(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }

    function testFailSafeAfterDonateSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        Hooks.safeAfterDonate(
            IHooks(mockHooks),
            address(this),
            IPoolManager.PoolKey(IERC20Minimal(address(this)), IERC20Minimal(address(this)), 1, 1, IHooks(mockHooks)),
            1,
            1
        );
    }
}
