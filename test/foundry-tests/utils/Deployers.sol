// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TestERC20} from "../../../contracts/test/TestERC20.sol";
import {Hooks} from "../../../contracts/libraries/Hooks.sol";
import {Currency} from "../../../contracts/types/Currency.sol";
import {IHooks} from "../../../contracts/interfaces/IHooks.sol";
import {IPoolManager} from "../../../contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "../../../contracts/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../../contracts/types/PoolId.sol";
import {FeeLibrary} from "../../../contracts/libraries/FeeLibrary.sol";
import {PoolKey} from "../../../contracts/types/PoolKey.sol";
import {Constants} from "../utils/Constants.sol";

contract Deployers {
    using FeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    uint160 constant SQRT_RATIO_1_1 = Constants.SQRT_RATIO_1_1;
    uint160 constant SQRT_RATIO_1_2 = Constants.SQRT_RATIO_1_2;
    uint160 constant SQRT_RATIO_1_4 = Constants.SQRT_RATIO_1_4;
    uint160 constant SQRT_RATIO_4_1 = Constants.SQRT_RATIO_4_1;

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new TestERC20(totalSupply);
        }
    }

    function createPool(PoolManager manager, IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        private
        returns (PoolKey memory key, PoolId id)
    {
        TestERC20[] memory tokens = deployTokens(2, 2 ** 255);
        key = PoolKey(
            Currency.wrap(address(tokens[0])),
            Currency.wrap(address(tokens[1])),
            fee,
            fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2),
            hooks
        );
        id = key.toId();
        manager.initialize(key, sqrtPriceX96);
    }

    function createFreshPool(IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (PoolManager manager, PoolKey memory key, PoolId id)
    {
        manager = createFreshManager();
        (key, id) = createPool(manager, hooks, fee, sqrtPriceX96);
        return (manager, key, id);
    }

    function createFreshManager() internal returns (PoolManager manager) {
        manager = new PoolManager(500000);
    }
}
