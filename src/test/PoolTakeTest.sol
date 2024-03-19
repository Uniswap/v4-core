// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract PoolTakeTest is PoolTestBase {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function take(PoolKey memory key, uint256 amount0, uint256 amount1) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) _testTake(data.key.currency0, data.sender, data.amount0);
        if (data.amount1 > 0) _testTake(data.key.currency1, data.sender, data.amount1);

        return abi.encode(0);
    }

    function _testTake(Currency currency, address sender, uint256 amount) internal {
        (uint256 userBalBefore, uint256 pmBalBefore, uint256 reserveBefore, int256 deltaBefore) =
            _fetchBalances(currency, sender, address(this));
        require(deltaBefore == 0, "deltaBefore is not equal to 0");

        _take(currency, sender, amount.toInt128(), true);

        (uint256 userBalAfter, uint256 pmBalAfter, uint256 reserveAfter, int256 deltaAfter) =
            _fetchBalances(currency, sender, address(this));
        require(deltaAfter == -amount.toInt128(), "deltaAfter is not equal to -amount.toInt128()");

        require(
            userBalAfter - userBalBefore == amount,
            "the difference between userBalAfter and userBalBefore is not equal to amount"
        );
        require(
            pmBalBefore - pmBalAfter == amount,
            "the difference between pmBalBefore and pmBalAfter is not equal to amount"
        );
        require(
            reserveBefore - reserveAfter == amount,
            "the difference between reserveBefore and reserveAfter is not equal to amount"
        );

        _settle(currency, sender, -amount.toInt128(), true);
    }
}
