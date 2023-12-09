// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Test} from "forge-std/Test.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";

contract PoolInitializeTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        uint160 sqrtPriceX96;
        bytes hookData;
    }

    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes memory hookData)
        external
        returns (int24 tick)
    {
        tick = abi.decode(
            manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, sqrtPriceX96, hookData))), (int24)
        );
    }

    function lockAcquired(address, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        int24 tick = manager.initialize(data.key, data.sqrtPriceX96, data.hookData);

        int256 delta0 = manager.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = manager.currencyDelta(address(this), data.key.currency1);
        uint256 nonZeroDC = manager.getLockNonzeroDeltaCount();

        if (!data.key.hooks.hasPermission(Hooks.ACCESS_LOCK_FLAG)) {
            assertEq(delta0, 0, "delta0");
            assertEq(delta1, 0, "delta1");
            assertEq(nonZeroDC, 0, "NonzeroDeltaCount");
        } else {
            // settle deltas
            if (delta0 > 0) _settle(data.key.currency0, data.sender, int128(delta0), true);
            if (delta1 > 0) _settle(data.key.currency1, data.sender, int128(delta1), true);
            if (delta0 < 0) _take(data.key.currency0, data.sender, int128(delta0), true);
            if (delta1 < 0) _take(data.key.currency1, data.sender, int128(delta1), true);
        }

        return abi.encode(tick);
    }
}
