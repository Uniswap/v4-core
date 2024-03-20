// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";

contract PoolDonateTest is PoolTestBase {
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
            manager.unlock(abi.encode(CallbackData(msg.sender, key, amount0, amount1, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, uint256 reserveBefore0, int256 deltaBefore0) =
            _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveBefore1, int256 deltaBefore1) =
            _fetchBalances(data.key.currency1, data.sender, address(this));

        require(deltaBefore0 == 0, "deltaBefore0 is not 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not 0");

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(reserveBefore0 == reserveAfter0, "reserveBefore0 is not equal to reserveAfter0");
        require(reserveBefore1 == reserveAfter1, "reserveBefore1 is not equal to reserveAfter1");
        require(deltaAfter0 == -int256(data.amount0), "deltaAfter0 is not equal to -int256(data.amount0)");
        require(deltaAfter1 == -int256(data.amount1), "deltaAfter1 is not equal to -int256(data.amount1)");

        if (deltaAfter0 < 0) _settle(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 < 0) _settle(data.key.currency1, data.sender, int128(deltaAfter1), true);
        if (deltaAfter0 > 0) _take(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 > 0) _take(data.key.currency1, data.sender, int128(deltaAfter1), true);

        return abi.encode(delta);
    }
}
