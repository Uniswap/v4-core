// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";

import "forge-std/console2.sol";

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
        console2.log("here");
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        manager.sync(data.key.currency0);
        manager.sync(data.key.currency1);
        (,, uint256 reserveBefore0, int256 deltaBefore0) =
            _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveBefore1, int256 deltaBefore1) =
            _fetchBalances(data.key.currency1, data.sender, address(this));

        assertEq(deltaBefore0, 0);
        assertEq(deltaBefore1, 0);

        console2.log(reserveBefore0);

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        // Must call sync again so that the reservesAfter0/reservesAfter1 are the most up to date
        // and check that there should be no change in balances from the donate call.
        manager.sync(data.key.currency0);
        manager.sync(data.key.currency1);
        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        assertEq(reserveBefore0, reserveAfter0);
        assertEq(reserveBefore1, reserveAfter1);

        console2.log(reserveAfter0);

        assertEq(deltaAfter0, int256(data.amount0));
        assertEq(deltaAfter1, int256(data.amount1));

        if (deltaAfter0 > 0) _settle(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 > 0) _settle(data.key.currency1, data.sender, int128(deltaAfter1), true);
        if (deltaAfter0 < 0) _take(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 < 0) _take(data.key.currency1, data.sender, int128(deltaAfter1), true);

        return abi.encode(delta);
    }
}
