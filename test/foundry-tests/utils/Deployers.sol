// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {TestERC20} from "../../../contracts/test/TestERC20.sol";
import {Hooks} from "../../../contracts/libraries/Hooks.sol";
import {Currency} from "../../../contracts/libraries/CurrencyLibrary.sol";
import {IHooks} from "../../../contracts/interfaces/IHooks.sol";
import {IPoolManager} from "../../../contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "../../../contracts/PoolManager.sol";
import {PoolId} from "../../../contracts/libraries/PoolId.sol";
import {Fees} from "../../../contracts/libraries/Fees.sol";

contract Deployers {
    using Fees for uint24;

    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    uint160 constant SQRT_RATIO_1_2 = 56022770974786139918731938227;
    uint160 constant SQRT_RATIO_1_4 = 39614081257132168796771975168;
    uint160 constant SQRT_RATIO_4_1 = 158456325028528675187087900672;

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new TestERC20(totalSupply);
        }
    }

    function createPool(PoolManager manager, IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        private
        returns (IPoolManager.PoolKey memory key, bytes32 id)
    {
        TestERC20[] memory tokens = deployTokens(2, 2 ** 255);
        key = IPoolManager.PoolKey(
            Currency.wrap(address(tokens[0])),
            Currency.wrap(address(tokens[1])),
            fee,
            fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2),
            hooks
        );
        id = PoolId.toId(key);
        manager.initialize(key, sqrtPriceX96);
    }

    function createFreshPool(IHooks hooks, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (PoolManager manager, IPoolManager.PoolKey memory key, bytes32 id)
    {
        manager = createFreshManager();
        (key, id) = createPool(manager, hooks, fee, sqrtPriceX96);
        return (manager, key, id);
    }

    function createFreshManager() internal returns (PoolManager manager) {
        manager = new PoolManager(500000);
    }
}
