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

    IPoolManager.PoolKey key;

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

        key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Fees.HOOK_SWAP_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        manager.initialize(key, SQRT_RATIO_1_1);
    }

    function testInitializeWithHookFee() public {
        manager.setHookFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.hookSwapFee, 0x50);
    }

    function testInitializeWithProtocolFeeAndHookFee() public {
        protocolFeeController.setFeeForPool(key.toId(), 0xA0); // 10% on 1 to 0 swaps
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolSwapFee, 0xA0);

        manager.setHookFee(key);
        (slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.hookSwapFee, 0x50);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        assertEq(manager.protocolFeesAccrued(currency1), 3); // 10% of 30 is 3
        assertEq(manager.hookFeesAccrued(key.toId(), currency1), 5); // 27 * .2 is 5.4 so 5 rounding down
    }

    function testCollectHookFees() public {
        protocolFeeController.setFeeForPool(key.toId(), 0xA0); // 10% on 1 to 0 swaps
        manager.setProtocolFeeController(IProtocolFeeController(protocolFeeController));
        manager.setProtocolFee(key);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.protocolSwapFee, 0xA0);

        manager.setHookFee(key);
        (slot0,,,) = manager.pools(key.toId());
        assertEq(slot0.hookSwapFee, 0x50);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-120, 120, 10e18);
        modifyPositionRouter.modifyPosition(key, params);
        // 1 for 0 swap
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 10000, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings(true, true)
        );

        vm.prank(address(hook));
        manager.collectHookFees(address(this), key, currency1, 0);

        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 5);
    }
}
