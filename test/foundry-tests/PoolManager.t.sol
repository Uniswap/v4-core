// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {PoolId} from "../../contracts/libraries/PoolId.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {Currency, CurrencyLibrary} from "../../contracts/libraries/CurrencyLibrary.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract PoolManagerTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using Pool for Pool.State;

    Pool.State state;
    PoolManager manager;
    PoolDonateTest donateRouter;
    PoolModifyPositionTest modifyPositionRouter;

    address ADDRESS_ZERO = address(0);

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();
        donateRouter = new PoolDonateTest(manager);
        modifyPositionRouter = new PoolModifyPositionTest(manager);

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 1 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 1 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(donateRouter), 1 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(donateRouter), 1 ether);
    }

    function testPoolManagerInitialize(IPoolManager.PoolKey memory key, uint160 sqrtPriceX96) public {
        // Assumptions tested in Pool.t.sol
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        // tested in Hooks.t.sol
        key.hooks = IHooks(address(0));

        if (key.fee >= 1000000 && key.fee != Hooks.DYNAMIC_FEE) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.FeeTooLarge.selector));
        } else if (key.tickSpacing > manager.MAX_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector));
        } else if (key.tickSpacing < manager.MIN_TICK_SPACING()) {
            vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector));
        } else if (!key.hooks.isValidHookAddress(key.fee)) {
            vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, address(key.hooks)));
        }

        manager.initialize(key, sqrtPriceX96);
    }

    function testDonateFailsIfNotInitialized() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    function testDonateFailsIfNoLiquidity(uint160 sqrtPriceX96) public {
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO);
        vm.assume(sqrtPriceX96 < TickMath.MAX_SQRT_RATIO);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, sqrtPriceX96);
        vm.expectRevert(abi.encodeWithSelector(Pool.NoLiquidityToReceiveFees.selector));
        donateRouter.donate(key, 100, 100);
    }

    // test successful donation if pool has liquidity
    function testDonateSucceedsWhenPoolHasLiquidity() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);
        snapStart("donate gas with 2 tokens");
        donateRouter.donate(key, 100, 200);
        snapEnd();

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(PoolId.toId(key));
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateSucceedsForNativeTokensWhenPoolHasLiquidity() public {
        vm.deal(address(this), 1 ether);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition{value: 1}(key, params);
        donateRouter.donate{value: 100}(key, 100, 200);

        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128,) = manager.pools(PoolId.toId(key));
        assertEq(feeGrowthGlobal0X128, 340282366920938463463374607431768211456);
        assertEq(feeGrowthGlobal1X128, 680564733841876926926749214863536422912);
    }

    function testDonateSucceedsWithBeforeAndAfterHooks() public {
        address hookAddr = address(uint160(Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG));

        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        MockHooks mockHooks = MockHooks(hookAddr);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: mockHooks,
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, bytes4(0xdeadbeef));

        // Fails at beforeDonate hook.
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200);

        // Fail at afterDonate hook.
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, mockHooks.beforeDonate.selector);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200);

        // Succeeds.
        mockHooks.setReturnValue(mockHooks.afterDonate.selector, mockHooks.afterDonate.selector);
        donateRouter.donate(key, 100, 200);
    }

    function testGasDonateOneToken() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 100,
            hooks: IHooks(address(0)),
            tickSpacing: 10
        });
        manager.initialize(key, SQRT_RATIO_1_1);

        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams(-60, 60, 100);
        modifyPositionRouter.modifyPosition(key, params);

        snapStart("donate gas with 1 token");
        donateRouter.donate(key, 100, 0);
        snapEnd();
    }

    fallback() external payable {}
}
