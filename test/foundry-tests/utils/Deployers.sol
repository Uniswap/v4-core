// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";
import {Hooks} from "../../../contracts/libraries/Hooks.sol";
import {Currency} from "../../../contracts/types/Currency.sol";
import {IHooks} from "../../../contracts/interfaces/IHooks.sol";
import {IPoolManager} from "../../../contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "../../../contracts/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../../contracts/types/PoolId.sol";
import {FeeLibrary} from "../../../contracts/libraries/FeeLibrary.sol";
import {PoolKey} from "../../../contracts/types/PoolKey.sol";
import {Constants} from "../utils/Constants.sol";
import {SortTokens} from "./SortTokens.sol";

contract Deployers {
    using FeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    bytes constant ZERO_BYTES = new bytes(0);

    uint160 constant SQRT_RATIO_1_1 = Constants.SQRT_RATIO_1_1;
    uint160 constant SQRT_RATIO_1_2 = Constants.SQRT_RATIO_1_2;
    uint160 constant SQRT_RATIO_1_4 = Constants.SQRT_RATIO_1_4;
    uint160 constant SQRT_RATIO_4_1 = Constants.SQRT_RATIO_4_1;

    function deployCurrencies(uint256 totalSupply) internal returns (Currency currency0, Currency currency1) {
        MockERC20[] memory tokens = deployTokens(2, totalSupply);
        return SortTokens.sort(tokens[0], tokens[1]);
    }

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (MockERC20[] memory tokens) {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", 18, totalSupply);
        }
    }

    function createPool(PoolManager manager, IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        public
        returns (PoolKey memory key, PoolId id)
    {
        (key, id) = createPool(manager, hooks, fee, sqrtPriceX96, ZERO_BYTES);
    }

    function createPool(PoolManager manager, IHooks hooks, uint24 fee, uint160 sqrtPriceX96, bytes memory initData)
        private
        returns (PoolKey memory key, PoolId id)
    {
        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        (Currency currency0, Currency currency1) = SortTokens.sort(tokens[0], tokens[1]);
        key = PoolKey(currency0, currency1, fee, fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2), hooks);
        id = key.toId();
        manager.initialize(key, sqrtPriceX96, initData);
    }

    function createKey(IHooks hooks, uint24 fee) internal returns (PoolKey memory key) {
        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        (Currency currency0, Currency currency1) = SortTokens.sort(tokens[0], tokens[1]);
        key = PoolKey(currency0, currency1, fee, fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2), hooks);
    }

    function createFreshPool(IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (PoolManager manager, PoolKey memory key, PoolId id)
    {
        (manager, key, id) = createFreshPool(hooks, fee, sqrtPriceX96, ZERO_BYTES);
    }

    function createFreshPool(IHooks hooks, uint24 fee, uint160 sqrtPriceX96, bytes memory initData)
        internal
        returns (PoolManager manager, PoolKey memory key, PoolId id)
    {
        manager = createFreshManager();
        (key, id) = createPool(manager, hooks, fee, sqrtPriceX96, initData);
        return (manager, key, id);
    }

    function createFreshManager() internal returns (PoolManager manager) {
        manager = new PoolManager(500000);
    }
}
