// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {console2} from "forge-std/console2.sol";

contract PoolDonateTest is PoolTestBase, Test {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, amount0, amount1, hookData))),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(address, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, uint256 reserveBefore0, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveBefore1, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender);

        assertEq(deltaBefore0, 0);
        assertEq(deltaBefore1, 0);

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        // Checks that the current hook is cleared if there is an access lock. Note that if this router is ever used in a nested lock this will fail.
        assertEq(address(manager.getCurrentHook()), address(0));

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender);

        console2.log("balances fetched");
        if (!data.key.hooks.hasPermissionToAccessLock()) {
            console2.log("no access lock");
            assertEq(reserveBefore0, reserveAfter0);
            assertEq(reserveBefore1, reserveAfter1);
            if (!data.key.hooks.hasPermissionToNoOp()) {
                console2.log("no noop");
                assertEq(deltaAfter0, int256(data.amount0));
                assertEq(deltaAfter1, int256(data.amount1));
            }
        }
        console2.log("after");
        if (delta == BalanceDeltaLibrary.MAXIMUM_DELTA) {
            console2.log("max delta");
            // Check that this hook is allowed to NoOp, then we can return as we dont need to settle
            assertTrue(data.key.hooks.hasPermissionToNoOp(), "Invalid NoOp returned");
            return abi.encode(delta);
        }
        console2.log("settles");
        if (deltaAfter0 > 0) _settle(data.key.currency0, data.sender, int128(deltaAfter0), true);
        console2.log("settle1");

        if (deltaAfter1 > 0) _settle(data.key.currency1, data.sender, int128(deltaAfter1), true);

        console2.log("settle2");
        if (deltaAfter0 < 0) _take(data.key.currency0, data.sender, int128(deltaAfter0), true);
        console2.log("take");
        if (deltaAfter1 < 0) _take(data.key.currency1, data.sender, int128(deltaAfter1), true);

        return abi.encode(delta);
    }
}
