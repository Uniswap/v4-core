// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {NoDelegateCall} from "../src/NoDelegateCall.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {ProxyPoolManager} from "../src/test/ProxyPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";

contract PoolManagerDelegateCall is Test, Deployers {
    // override to use ProxyPoolManager
    function deployFreshManager() internal virtual override {
        IPoolManager delegateManager = new PoolManager(500000);
        manager = new ProxyPoolManager(address(delegateManager), 500000);
    }

    function setUp() public {
        deployFreshManagerAndRouters(); // no liquidity needed
    }

    function test_modifyLiquidity_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_swap_noDelegateCall() public {
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_donate_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_take_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        takeRouter.take(key, 1, 1);
    }

    function test_settle_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        settleRouter.settle(key);
    }

    function test_mint_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        claimsRouter.mint(currency0, address(this), 1);
    }

    function test_burn_noDelegateCall() public {
        vm.expectRevert(NoDelegateCall.DelegateCallNotAllowed.selector);
        claimsRouter.burn(currency0, address(this), 1);
    }
}
