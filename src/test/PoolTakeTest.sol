// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract PoolTakeTest is Test, PoolTestBase {
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
        manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) _testTake(data.key.currency0, data.sender, data.amount0);
        if (data.amount1 > 0) _testTake(data.key.currency1, data.sender, data.amount1);

        return abi.encode(0);
    }

    function _testTake(Currency currency, address sender, uint256 amount) internal {
        (uint256 userBalBefore, uint256 pmBalBefore, uint256 reserveBefore, int256 deltaBefore) =
            _fetchBalances(currency, sender);
        assertEq(deltaBefore, 0);

        _take(currency, sender, -(amount.toInt128()), true);

        (uint256 userBalAfter, uint256 pmBalAfter, uint256 reserveAfter, int256 deltaAfter) =
            _fetchBalances(currency, sender);
        assertEq(deltaAfter, amount.toInt128());

        assertEq(userBalAfter - userBalBefore, amount);
        assertEq(pmBalBefore - pmBalAfter, amount);
        assertEq(reserveBefore - reserveAfter, amount);
        assertEq(reserveBefore - reserveAfter, amount);

        _settle(currency, sender, amount.toInt128(), true);
    }
}
