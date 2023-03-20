pragma solidity ^0.8.15;

import {TestERC20} from '../../../contracts/test/TestERC20.sol';
import {Currency} from '../../../contracts/libraries/CurrencyLibrary.sol';
import {IHooks} from '../../../contracts/interfaces/IHooks.sol';
import {IPoolManager} from '../../../contracts/interfaces/IPoolManager.sol';
import {PoolManager} from '../../../contracts/PoolManager.sol';
import {PoolId} from '../../../contracts/libraries/PoolId.sol';

contract Deployers {
    function deployTokens(uint8 count, uint256 totalSupply) public returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new TestERC20(totalSupply);
        }
    }

    function createPool(
        PoolManager manager,
        IHooks hooks,
        uint160 sqrtPriceX96
    ) public returns (IPoolManager.PoolKey memory key, bytes32 id) {
        TestERC20[] memory tokens = deployTokens(2, 2**255);
        key = IPoolManager.PoolKey(
            Currency.wrap(address(tokens[0])),
            Currency.wrap(address(tokens[1])),
            3000,
            60,
            hooks
        );
        id = PoolId.toId(key);
        manager.initialize(key, sqrtPriceX96);
    }

    function createFreshPool(IHooks hooks, uint160 sqrtPriceX96)
        public
        returns (
            PoolManager manager,
            IPoolManager.PoolKey memory key,
            bytes32 id
        )
    {
        manager = new PoolManager(500000);
        (key, id) = createPool(manager, hooks, sqrtPriceX96);
        return (manager, key, id);
    }
}
