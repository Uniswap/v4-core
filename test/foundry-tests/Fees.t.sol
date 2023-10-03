// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {FeeLibrary} from "../../contracts/libraries/FeeLibrary.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {IFees} from "../../contracts/interfaces/IFees.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolIdLibrary} from "../../contracts/types/PoolId.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/types/Currency.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ProtocolFeeControllerTest} from "../../contracts/test/ProtocolFeeControllerTest.sol";
import {IProtocolFeeController} from "../../contracts/interfaces/IProtocolFeeController.sol";
import {Fees} from "../../contracts/Fees.sol";
import {BalanceDelta} from "../../contracts/types/BalanceDelta.sol";
import {PoolKey} from "../../contracts/types/PoolKey.sol";

contract FeesTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using Pool for Pool.State;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Pool.State state;
    PoolManager manager;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    ProtocolFeeControllerTest protocolFeeController;

    MockHooks hook;

    // key0 hook enabled fee on swap
    PoolKey key0;
    // key1 hook enabled fee on withdraw
    PoolKey key1;
    // key2 hook enabled fee on swap and withdraw
    PoolKey key2;
    // key3 no hook
    PoolKey key3;

    bool _zeroForOne = true;
    bool _oneForZero = false;

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

        key0 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.HOOK_SWAP_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        key2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | FeeLibrary.HOOK_SWAP_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        key3 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(3000),
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        manager.initialize(key0, SQRT_RATIO_1_1, ZERO_BYTES);
        manager.initialize(key1, SQRT_RATIO_1_1, ZERO_BYTES);
        manager.initialize(key2, SQRT_RATIO_1_1, ZERO_BYTES);
        manager.initialize(key3, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testInitializeFailsNoHook() public {
        PoolKey memory key4 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | FeeLibrary.HOOK_SWAP_FEE_FLAG | uint24(3000),
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(0)));
        manager.initialize(key4, SQRT_RATIO_1_1, ZERO_BYTES);

        key4 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.DYNAMIC_FEE_FLAG,
            hooks: IHooks(address(0)),
            tickSpacing: 60
        });

        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(0)));
        manager.initialize(key4, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function testInitializeHookSwapFee(uint16 fee) public {
        vm.assume(fee < 2 ** 12);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), 0);

        hook.setSwapFee(key0, fee);
        manager.setHookFees(key0);

        (slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), fee);
        assertEq(getWithdrawFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);
    }

    function testInitializeHookWithdrawFee(uint16 fee) public {
        vm.assume(fee < 2 ** 12);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key1.toId());
        assertEq(getWithdrawFee(slot0.hookFees), 0);

        hook.setWithdrawFee(key1, fee);
        manager.setHookFees(key1);

        (slot0,,,) = manager.pools(key1.toId());
        assertEq(getWithdrawFee(slot0.hookFees), fee);
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);
    }

    function testInitializeBothHookFee(uint16 swapFee, uint16 withdrawFee) public {
        vm.assume(swapFee < 2 ** 12 && withdrawFee < 2 ** 12);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key2.toId());
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getWithdrawFee(slot0.hookFees), 0);

        hook.setSwapFee(key2, swapFee);
        hook.setWithdrawFee(key2, withdrawFee);
        manager.setHookFees(key2);

        (slot0,,,) = manager.pools(key2.toId());
        assertEq(getSwapFee(slot0.hookFees), swapFee);
        assertEq(getWithdrawFee(slot0.hookFees), withdrawFee);
    }

    function testInitializeHookProtocolSwapFee(uint16 hookSwapFee, uint16 protocolSwapFee) public {
        vm.assume(hookSwapFee < 2 ** 12 && protocolSwapFee < 2 ** 12);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), 0);

        protocolFeeController.setSwapFeeForPool(key0.toId(), protocolSwapFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));

        uint16 protocolSwapFee1 = protocolSwapFee >> 6;
        uint16 protocolSwapFee0 = protocolSwapFee % 64;

        if ((protocolSwapFee0 != 0 && protocolSwapFee0 < 4) || (protocolSwapFee1 != 0 && protocolSwapFee1 < 4)) {
            protocolSwapFee = 0;
            vm.expectRevert(IFees.FeeTooLarge.selector);
        }
        manager.setProtocolFees(key0);

        hook.setSwapFee(key0, hookSwapFee);
        manager.setHookFees(key0);

        (slot0,,,) = manager.pools(key0.toId());

        assertEq(getWithdrawFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.hookFees), hookSwapFee);
        assertEq(getSwapFee(slot0.protocolFees), protocolSwapFee);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);
    }

    function testInitializeAllFees(
        uint16 hookSwapFee,
        uint16 hookWithdrawFee,
        uint16 protocolSwapFee,
        uint16 protocolWithdrawFee
    ) public {
        vm.assume(
            hookSwapFee < 2 ** 12 && hookWithdrawFee < 2 ** 12 && protocolSwapFee < 2 ** 12
                && protocolWithdrawFee < 2 ** 12
        );

        (Pool.Slot0 memory slot0,,,) = manager.pools(key2.toId());
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getWithdrawFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);

        protocolFeeController.setSwapFeeForPool(key2.toId(), protocolSwapFee);
        protocolFeeController.setWithdrawFeeForPool(key2.toId(), protocolWithdrawFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));

        uint16 protocolSwapFee1 = protocolSwapFee >> 6;
        uint16 protocolSwapFee0 = protocolSwapFee % 64;
        uint16 protocolWithdrawFee1 = protocolWithdrawFee >> 6;
        uint16 protocolWithdrawFee0 = protocolWithdrawFee % 64;

        if (
            (protocolSwapFee1 != 0 && protocolSwapFee1 < 4) || (protocolSwapFee0 != 0 && protocolSwapFee0 < 4)
                || (protocolWithdrawFee1 != 0 && protocolWithdrawFee1 < 4)
                || (protocolWithdrawFee0 != 0 && protocolWithdrawFee0 < 4)
        ) {
            protocolSwapFee = 0;
            protocolWithdrawFee = 0;
            vm.expectRevert(IFees.FeeTooLarge.selector);
        }
        manager.setProtocolFees(key2);

        hook.setSwapFee(key2, hookSwapFee);
        hook.setWithdrawFee(key2, hookWithdrawFee);
        manager.setHookFees(key2);

        (slot0,,,) = manager.pools(key2.toId());

        assertEq(getWithdrawFee(slot0.hookFees), hookWithdrawFee);
        assertEq(getSwapFee(slot0.hookFees), hookSwapFee);
        assertEq(getSwapFee(slot0.protocolFees), protocolSwapFee);
        assertEq(getWithdrawFee(slot0.protocolFees), protocolWithdrawFee);
    }

    function testProtocolFeeOnWithdrawalRemainsZeroIfNoHookWithdrawalFeeSet(
        uint16 hookSwapFee,
        uint16 protocolWithdrawFee
    ) public {
        vm.assume(hookSwapFee < 2 ** 12 && protocolWithdrawFee < 2 ** 12);
        vm.assume(protocolWithdrawFee >> 6 >= 4);
        vm.assume(protocolWithdrawFee % 64 >= 4);

        // On a pool whose hook has not set a withdraw fee, the protocol should not accrue any value even if it has set a withdraw fee.
        hook.setSwapFee(key0, hookSwapFee);
        manager.setHookFees(key0);

        // set fee on the fee controller
        protocolFeeController.setWithdrawFeeForPool(key0.toId(), protocolWithdrawFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getWithdrawFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.hookFees), hookSwapFee);
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), protocolWithdrawFee);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 10e18);
        modifyPositionRouter.modifyPosition(key0, params, ZERO_BYTES);

        IPoolManager.ModifyPositionParams memory params2 = IPoolManager.ModifyPositionParams(-60, 60, -10e18);
        modifyPositionRouter.modifyPosition(key0, params2, ZERO_BYTES);

        // Fees dont accrue when key.fee does not specify a withdrawal param even if the protocol fee is set.
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency0), 0);
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency1), 0);
    }

    // function testFeeOutOfBoundsReverts(uint16 newFee) external {
    //     newFee = uint16(bound(newFee, 2 ** 12, type(uint16).max));

    //     hook.setSwapFee(key0, newFee);
    //     vm.expectRevert(abi.encodeWithSelector(IFees.FeeDenominatorOutOfBounds.selector, newFee));
    //     manager.setHookFees(key0);

    //     hook.setWithdrawFee(key0, newFee);
    //     vm.expectRevert(abi.encodeWithSelector(IFees.FeeDenominatorOutOfBounds.selector, newFee));
    //     manager.setHookFees(key0);

    //     manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));

    //     protocolFeeController.setSwapFeeForPool(key0.toId(), newFee);
    //     vm.expectRevert(abi.encodeWithSelector(IFees.FeeDenominatorOutOfBounds.selector, newFee));
    //     manager.setProtocolFees(key0);

    //     protocolFeeController.setWithdrawFeeForPool(key0.toId(), newFee);
    //     vm.expectRevert(abi.encodeWithSelector(IFees.FeeDenominatorOutOfBounds.selector, newFee));
    //     manager.setProtocolFees(key0);
    // }

    function testHookWithdrawFeeProtocolWithdrawFee(uint16 hookWithdrawFee, uint16 protocolWithdrawFee) public {
        vm.assume(protocolWithdrawFee < 2 ** 12);
        vm.assume(hookWithdrawFee < 2 ** 12);
        vm.assume(protocolWithdrawFee >> 6 >= 4);
        vm.assume(protocolWithdrawFee % 64 >= 4);

        hook.setWithdrawFee(key1, hookWithdrawFee);
        manager.setHookFees(key1);

        protocolFeeController.setWithdrawFeeForPool(key1.toId(), protocolWithdrawFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key1);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key1.toId());

        assertEq(getWithdrawFee(slot0.hookFees), hookWithdrawFee);
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), protocolWithdrawFee);

        int256 liquidityDelta = 10000;
        // The underlying amount for a liquidity delta of 10000 is 29.
        uint256 underlyingAmount0 = 29;
        uint256 underlyingAmount1 = 29;

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, liquidityDelta);
        BalanceDelta delta = modifyPositionRouter.modifyPosition(key1, params, ZERO_BYTES);

        // Fees dont accrue for positive liquidity delta.
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(manager.hookFeesAccrued(address(key1.hooks), currency0), 0);
        assertEq(manager.hookFeesAccrued(address(key1.hooks), currency1), 0);

        IPoolManager.ModifyPositionParams memory params2 = IPoolManager.ModifyPositionParams(-60, 60, -liquidityDelta);
        delta = modifyPositionRouter.modifyPosition(key1, params2, ZERO_BYTES);

        uint16 hookFee0 = (hookWithdrawFee % 64);
        uint16 hookFee1 = (hookWithdrawFee >> 6);
        uint16 protocolFee0 = (protocolWithdrawFee % 64);
        uint16 protocolFee1 = (protocolWithdrawFee >> 6);

        // Fees should accrue to both the protocol and hook.
        uint256 initialHookAmount0 = hookFee0 == 0 ? 0 : underlyingAmount0 / hookFee0;
        uint256 initialHookAmount1 = hookFee1 == 0 ? 0 : underlyingAmount1 / hookFee1;

        uint256 expectedProtocolAmount0 = protocolFee0 == 0 ? 0 : initialHookAmount0 / protocolFee0;
        uint256 expectedProtocolAmount1 = protocolFee1 == 0 ? 0 : initialHookAmount1 / protocolFee1;
        // Adjust the hook fee amounts after the protocol fee is taken.
        uint256 expectedHookFee0 = initialHookAmount0 - expectedProtocolAmount0;
        uint256 expectedHookFee1 = initialHookAmount1 - expectedProtocolAmount1;

        assertEq(manager.protocolFeesAccrued(currency0), expectedProtocolAmount0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolAmount1);
        assertEq(manager.hookFeesAccrued(address(key1.hooks), currency0), expectedHookFee0);
        assertEq(manager.hookFeesAccrued(address(key1.hooks), currency1), expectedHookFee1);
    }

    function testNoHookProtocolFee(uint16 protocolSwapFee, uint16 protocolWithdrawFee) public {
        vm.assume(protocolSwapFee < 2 ** 12 && protocolWithdrawFee < 2 ** 12);

        vm.assume(protocolSwapFee >> 6 >= 4);
        vm.assume(protocolSwapFee % 64 >= 4);
        vm.assume(protocolWithdrawFee >> 6 >= 4);
        vm.assume(protocolWithdrawFee % 64 >= 4);

        protocolFeeController.setSwapFeeForPool(key3.toId(), protocolSwapFee);
        protocolFeeController.setWithdrawFeeForPool(key3.toId(), protocolWithdrawFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key3);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key3.toId());
        assertEq(getWithdrawFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.hookFees), 0);
        assertEq(getSwapFee(slot0.protocolFees), protocolSwapFee);
        assertEq(getWithdrawFee(slot0.protocolFees), protocolWithdrawFee);

        int256 liquidityDelta = 10000;
        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, liquidityDelta);
        modifyPositionRouter.modifyPosition(key3, params, ZERO_BYTES);

        // Fees dont accrue for positive liquidity delta.
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);
        assertEq(manager.hookFeesAccrued(address(key3.hooks), currency0), 0);
        assertEq(manager.hookFeesAccrued(address(key3.hooks), currency1), 0);

        IPoolManager.ModifyPositionParams memory params2 = IPoolManager.ModifyPositionParams(-60, 60, -liquidityDelta);
        modifyPositionRouter.modifyPosition(key3, params2, ZERO_BYTES);

        uint16 protocolSwapFee1 = (protocolSwapFee >> 6);

        // No fees should accrue bc there is no hook so the protocol cant take withdraw fees.
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), 0);

        // add larger liquidity
        params = IPoolManager.ModifyPositionParams(-60, 60, 10e18);
        modifyPositionRouter.modifyPosition(key3, params, ZERO_BYTES);

        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key3,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );
        // key3 pool is 30 bps => 10000 * 0.003 (.3%) = 30
        uint256 expectedSwapFeeAccrued = 30;

        uint256 expectedProtocolAmount1 = protocolSwapFee1 == 0 ? 0 : expectedSwapFeeAccrued / protocolSwapFee1;
        assertEq(manager.protocolFeesAccrued(currency0), 0);
        assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolAmount1);
    }

    function testProtocolSwapFeeAndHookSwapFeeSameDirection() public {
        uint16 protocolFee = _computeFee(_oneForZero, 10); // 10% on 1 to 0 swaps
        protocolFeeController.setSwapFeeForPool(key0.toId(), protocolFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.protocolFees), protocolFee);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);

        uint16 hookFee = _computeFee(_oneForZero, 5); // 20% on 1 to 0 swaps
        hook.setSwapFee(key0, hookFee);
        manager.setHookFees(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), hookFee);
        assertEq(getWithdrawFee(slot0.hookFees), 0);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params, ZERO_BYTES);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency1), 3); // 10% of 30 is 3
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency1), 5); // 27 * .2 is 5.4 so 5 rounding down
    }

    function testInitializeWithSwapProtocolFeeAndHookFeeDifferentDirections() public {
        uint16 protocolFee = _computeFee(_oneForZero, 10); // 10% fee on 1 to 0 swaps
        protocolFeeController.setSwapFeeForPool(key0.toId(), protocolFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.protocolFees), protocolFee);
        assertEq(getWithdrawFee(slot0.protocolFees), 0);

        uint16 hookFee = _computeFee(_zeroForOne, 5); // 20% on 0 to 1 swaps

        hook.setSwapFee(key0, hookFee);
        manager.setHookFees(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), hookFee);
        assertEq(getWithdrawFee(slot0.hookFees), 0);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params, ZERO_BYTES);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency1), 3); // 10% of 30 is 3
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency1), 0); // hook fee only taken on 0 to 1 swaps
    }

    function testSwapWithProtocolFeeAllAndHookFeeAllButOnlySwapFlag() public {
        // Protocol should not be able to withdraw since the hook withdraw fee is not set
        uint16 protocolFee = _computeFee(_oneForZero, 4) | _computeFee(_zeroForOne, 4); // max fees on both amounts
        protocolFeeController.setWithdrawFeeForPool(key0.toId(), protocolFee); //
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.protocolFees), 0);
        assertEq(getWithdrawFee(slot0.protocolFees), protocolFee); // successfully sets the fee, but is never applied

        uint16 hookSwapFee = _computeFee(_oneForZero, 4); // 25% on 1 to 0 swaps
        uint16 hookWithdrawFee = _computeFee(_oneForZero, 4) | _computeFee(_zeroForOne, 4); // max fees on both amounts
        hook.setSwapFee(key0, hookSwapFee);
        hook.setWithdrawFee(key0, hookWithdrawFee);
        manager.setHookFees(key0);
        (slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), hookSwapFee);
        assertEq(getWithdrawFee(slot0.hookFees), 0); // Even though the contract sets a withdraw fee it will not be applied bc the pool key.fee did not assert a withdraw flag.

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params, ZERO_BYTES);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );

        assertEq(manager.protocolFeesAccrued(currency1), 0); // No protocol fee was accrued on swap
        assertEq(manager.protocolFeesAccrued(currency0), 0); // No protocol fee was accrued on swap
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency1), 7); // 25% on 1 to 0, 25% of 30 is 7.5 so 7

        modifyPositionRouter.modifyPosition(key0, IPoolManager.ModifyPositionParams(-120, 120, -10e18), ZERO_BYTES);

        assertEq(manager.protocolFeesAccrued(currency1), 0); // No protocol fee was accrued on withdraw
        assertEq(manager.protocolFeesAccrued(currency0), 0); // No protocol fee was accrued on withdraw
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency1), 7); // Same amount of fees for hook.
        assertEq(manager.hookFeesAccrued(address(key0.hooks), currency0), 0); // Same amount of fees for hook.
    }

    function testCollectFees() public {
        uint16 protocolFee = _computeFee(_oneForZero, 10); // 10% on 1 to 0 swaps
        protocolFeeController.setSwapFeeForPool(key0.toId(), protocolFee);
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFees(key0);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.protocolFees), protocolFee);

        uint16 hookFee = _computeFee(_oneForZero, 5); // 20% on 1 to 0 swaps
        hook.setSwapFee(key0, hookFee);
        manager.setHookFees(key0);

        (slot0,,,) = manager.pools(key0.toId());
        assertEq(getSwapFee(slot0.hookFees), hookFee);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key0, params, ZERO_BYTES);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key0,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );

        uint256 expectedProtocolFees = 3; // 10% of 30 is 3
        vm.prank(address(protocolFeeController));
        manager.collectProtocolFees(address(protocolFeeController), currency1, 0);
        assertEq(currency1.balanceOf(address(protocolFeeController)), expectedProtocolFees);

        uint256 expectedHookFees = 5; // 20% of 27 (30-3) is 5.4, round down is 5
        vm.prank(address(hook));
        // Addr(0) recipient will be the hook.
        manager.collectHookFees(address(hook), currency1, 0);
        assertEq(currency1.balanceOf(address(hook)), expectedHookFees);
    }

    // If zeroForOne is true, then value is set on the lower bits. If zeroForOne is false, then value is set on the higher bits.
    function _computeFee(bool zeroForOne, uint16 value) internal pure returns (uint16 fee) {
        if (zeroForOne) {
            fee = value % 64;
        } else {
            fee = value << 6;
        }
    }

    function getSwapFee(uint24 feesStorage) internal pure returns (uint16) {
        return uint16(feesStorage >> 12);
    }

    function getWithdrawFee(uint24 feesStorage) internal pure returns (uint16) {
        return uint16(feesStorage & 0xFFF);
    }
}
