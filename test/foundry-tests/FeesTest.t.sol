// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/libraries/CurrencyLibrary.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolLockTest} from "../../contracts/test/PoolLockTest.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {ProtocolFeeControllerTest} from "../../contracts/test/ProtocolFeeControllerTest.sol";
import {IProtocolFeeController} from "../../contracts/interfaces/IProtocolFeeController.sol";
import {Fees} from "../../contracts/libraries/Fees.sol";

contract FeesTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using Pool for Pool.State;
    using PoolId for IPoolManager.PoolKey;

    Pool.State state;
    PoolManager manager;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    ProtocolFeeControllerTest protocolFeeController;

    MockHooks hook;

    IPoolManager.PoolKey key0;
    IPoolManager.PoolKey key1;

    address ADDRESS_ZERO = address(0);

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();

        modifyPositionRouter = new PoolModifyPositionTest(manager);
        swapRouter = new PoolSwapTest(manager);
        protocolFeeController = new ProtocolFeeControllerTest();

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 10 ether);

        address hookAddr = address(99); // can't be a zero address, but does not have to have any other hook flags specified
        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        hook = MockHooks(hookAddr);

        key0 = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Fees.HOOK_SWAP_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        key1 = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Fees.HOOK_WITHDRAW_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        manager.initialize(key0, SQRT_RATIO_1_1);
        manager.initialize(key1, SQRT_RATIO_1_1);
    }

    function testInitializeWithHookSwapFee() public {
        // 0x50
        // 20% fee for 1 to 0 swaps
        hook.setSwapFee(key0, 0x50);
        manager.setHookFee(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.hookSwapFee, 0x50);
        assertEq(slot0.hookWithdrawFee, 0);
        assertEq(slot0.protocolSwapFee, 0);
        assertEq(slot0.protocolWithdrawFee, 0);
    }

    function testInitializeWithHookWithdrawFee() public {
        // 0x0A
        // 10% fee on amount0
        hook.setWithdrawFee(key1, 0x0A);
        manager.setHookFee(key1);
        (Pool.Slot0 memory slot0,,,) = manager.pools(key1.toId());
        assertEq(slot0.hookWithdrawFee, 0x0A);
        assertEq(slot0.hookSwapFee, 0);
        assertEq(slot0.protocolSwapFee, 0);
        assertEq(slot0.protocolWithdrawFee, 0);
    }

    function testInitializeWithSwapProtocolFeeAndHookFee() public {
        protocolFeeController.setSwapFeeForPool(key0.toId(), 0xA0); // 10% on 1 to 0 swaps
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.protocolSwapFee, 0xA0);
        assertEq(slot0.protocolWithdrawFee, 0);

        hook.setSwapFee(key0, 0x50); // 20% on 1 to 0 swaps
        manager.setHookFee(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.hookSwapFee, 0x50);
        assertEq(slot0.hookWithdrawFee, 0);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        assertEq(manager.protocolFeesAccrued(currency1), 3); // 10% of 30 is 3
        assertEq(manager.hookFeesAccrued(key0.toId(), currency1), 5); // 27 * .2 is 5.4 so 5 rounding down
    }

    function testInitializeWithSwapProtocolFeeAndHookFeeDifferentDirections() public {
        protocolFeeController.setSwapFeeForPool(key0.toId(), 0xA0); // 10% on 1 to 0 swaps
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.protocolSwapFee, 0xA0);
        assertEq(slot0.protocolWithdrawFee, 0);

        hook.setSwapFee(key0, 0x05); // 20% on 0 to 1 swaps
        manager.setHookFee(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.hookSwapFee, 0x05);
        assertEq(slot0.hookWithdrawFee, 0);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        assertEq(manager.protocolFeesAccrued(currency1), 3); // 10% of 30 is 3
        assertEq(manager.hookFeesAccrued(key0.toId(), currency1), 0); // hook fee only taken on 0 to 1 swaps
    }

    function testInitializeWithWithdrawProtocolFeeAndSwapHookFee() public {
        // Protocol should not be able to withdraw since the hook withdraw fee is not set
        protocolFeeController.setWithdrawFeeForPool(key0.toId(), 0x44); // max fees on both amounts
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.protocolSwapFee, 0);
        assertEq(slot0.protocolWithdrawFee, 0x44); // successfully sets the fee, but is never applied
        // todo, should we not even allow it to be set?

        hook.setSwapFee(key0, 0x40); // 25% on 1 to 0 swaps
        hook.setWithdrawFee(key0, 0xFF);
        manager.setHookFee(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.hookSwapFee, 0x40);
        assertEq(slot0.hookWithdrawFee, 0); // Even though the contract sets a withdraw fee it will not be applied bc the pool key.fee did not assert a withdraw flag.

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        assertEq(manager.protocolFeesAccrued(currency1), 0); // No protocol fee was accrued on swap
        assertEq(manager.protocolFeesAccrued(currency0), 0); // No protocol fee was accrued on swap
        assertEq(manager.hookFeesAccrued(key0.toId(), currency1), 7); // 25% on 1 to 0, 25% of 30 is 7.5 so 7

        modifyPositionRouter.modifyPosition(key0, IPoolManager.ModifyPositionParams(-120, 120, -10e18));
        //TODO update router to take amount out of pool

        assertEq(manager.protocolFeesAccrued(currency1), 0); // No protocol fee was accrued on withdraw
        assertEq(manager.protocolFeesAccrued(currency0), 0); // No protocol fee was accrued on withdraw
        assertEq(manager.hookFeesAccrued(key0.toId(), currency1), 7); // Same amount of fees for hook.
        assertEq(manager.hookFeesAccrued(key0.toId(), currency0), 0); // Same amount of fees for hook.
    }

    function testCollectHookFees() public {
        protocolFeeController.setSwapFeeForPool(key0.toId(), 0xA0); // 10% on 1 to 0 swaps
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.protocolSwapFee, 0xA0);

        hook.setSwapFee(key0, 0x50);

        manager.setHookFee(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(slot0.hookSwapFee, 0x50);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        vm.prank(address(hook));
        manager.collectHookFees(address(hook), key0, currency1, 0);

        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 5);
    }
}
