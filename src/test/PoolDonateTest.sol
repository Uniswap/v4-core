// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {TestBase} from "./TestBase.sol";

contract PoolDonateTest is TestBase {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _manager) TestBase(_manager) {}

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

        (,, uint256 reserveBefore0, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveBefore1, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender);

        assert(deltaBefore0 == 0 && deltaBefore1 == 0);

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender);

        assert(reserveBefore0 == reserveAfter0);
        assert(reserveBefore1 == reserveAfter1);
        assert(deltaAfter0 == int256(data.amount0));
        assert(deltaAfter1 == int256(data.amount1));

        if (data.amount0 > 0) _settle(data.key.currency0, data.sender, delta.amount0(), true);
        if (data.amount1 > 0) _settle(data.key.currency1, data.sender, delta.amount1(), true);

        return abi.encode(delta);
    }
}
