// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {OverrideHook} from "../../contracts/test/OverrideHook.sol";
import {PoolKey} from "../../contracts/types/PoolKey.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {PoolId} from "../../contracts/types/PoolId.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {CurrencyLibrary, Currency} from "../../contracts/types/Currency.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract OverrideHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    IPoolManager public manager;
    IHooks public hook;
    PoolKey public key;
    PoolSwapTest public swapRouter;
    PoolModifyPositionTest public positionRouter;
    PoolId public id;

    function setUp() public {
        manager = createFreshManager();

        OverrideHook impl = new OverrideHook(manager);
        address hookAddress =
            address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.OVERRIDE_FLAG));

        // Note: etch only copies over RUNTIME code, not creation code, so manager is the 0 address
        // setting the manager is a fix until deployCodeTo is fixed? or re-added
        // deployCodeTo("OverrideHook.sol", abi.encode(address(manager)), hookAddress);
        vm.etch(hookAddress, address(impl).code);
        hook = IHooks(hookAddress);
        OverrideHook(address(hook)).setManager(address(manager));

        (key, id) = createPool(PoolManager(payable(address(manager))), hook, 3000, SQRT_RATIO_1_1, ZERO_BYTES);

        swapRouter = new PoolSwapTest(manager);
        positionRouter = new PoolModifyPositionTest(manager);

        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(swapRouter), 10 ether);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(positionRouter), 10 ether);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(positionRouter), 10 ether);
    }

    // test successful deposit

    struct ModifyPositionParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // how to modify the liquidity
        int256 liquidityDelta;
    }

    function testModifyPositionWithOverrideHook() public {
        // Will deposit 100 of currency1 into the pool
        IPoolManager.ModifyPositionParams memory params = IPoolManager.ModifyPositionParams({
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            liquidityDelta: 100
        });
        // Encode this address to send to the hook to account an lpBalance for testing purposes
        positionRouter.modifyPosition(key, params, abi.encode(address(this)));

        // Expect that the hook has a balance of 100 1155s in currency1
        assertEq(manager.balanceOf(address(key.hooks), key.currency1.toId()), 100);
        // Expect that the pool manager's balance increases by 100
        assertEq(key.currency1.balanceOf(address(manager)), 100);
        // Expect that this address is credited 100 on the hooks lpBalance mapping
        assertEq(OverrideHook(address(key.hooks)).lpBalances(address(this)), 100);
    }

    function testSwapWithOverrideHook() public {
        // Give the hook liquidity in currency1
        positionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: 50
            }),
            abi.encode(address(this))
        );

        // Expect that the hook now has 50 1155s of currency1
        assertEq(manager.balanceOf(address(key.hooks), key.currency1.toId()), 50);
        // Assert that this address has deposited 50 in the hook
        assertEq(OverrideHook(address(key.hooks)).lpBalances(address(this)), 50);

        // Prep the swap.
        // Should get 50 currency1 for 100 currency0
        OverrideHook(address(key.hooks)).setExchangeRate(2);
        // Create swap params
        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: 0});
        // The router will withdraw token1 that the hook sends in, and it will transfer in token0 to negate the delta from the hook's mint
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});
        // No need to send extra data to the hook
        uint256 currency1Before = key.currency1.balanceOf(address(this));
        uint256 currency0Before = key.currency0.balanceOf(address(this));
        uint256 managerCurrency0Before = key.currency0.balanceOf(address(manager));
        uint256 managerCurrency1Before = key.currency1.balanceOf(address(manager));
        swapRouter.swap(key, params, settings, ZERO_BYTES);

        // Expect that the hook has 100 1155 of currency0
        assertEq(manager.balanceOf(address(key.hooks), key.currency0.toId()), 100);
        // Expect that the hook has 0 1155 of currency1 (it burned 50 which the router takes)
        assertEq(manager.balanceOf(address(key.hooks), key.currency1.toId()), 0);

        // Expect that this address gives 100 of currency0
        assertEq(key.currency0.balanceOf(address(this)), currency0Before - 100);
        // Expect that this address receives 50 of currency1
        assertEq(key.currency1.balanceOf(address(this)), currency1Before + 50);

        // Expect that the balance of the pool increases by 100 of currency0
        assertEq(key.currency0.balanceOf(address(manager)), managerCurrency0Before + 100);
        // Expect that the balance of the pool decreases by 50 of currency1
        assertEq(key.currency1.balanceOf(address(manager)), managerCurrency1Before - 50);
    }
}
