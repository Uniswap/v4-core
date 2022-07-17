pragma solidity ^0.8.15;

import {TestERC20} from '../../../contracts/test/TestERC20.sol';
import {IHooks} from '../../../contracts/interfaces/IHooks.sol';
import {IERC20Minimal} from '../../../contracts/interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../../../contracts/interfaces/IPoolManager.sol';
import {PoolManager} from '../../../contracts/PoolManager.sol';
import {PoolId} from '../../../contracts/libraries/PoolId.sol';
import {Hooks} from '../../../contracts/libraries/Hooks.sol';

contract Deployers {
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    function deployTokens(uint8 count, uint256 totalSupply) public returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new TestERC20(totalSupply);
        }
    }

    function newPoolKey(IHooks hooks) public returns (IPoolManager.PoolKey memory key, bytes32 id)  {
      TestERC20[] memory tokens = deployTokens(2, 2**255);
      key = IPoolManager.PoolKey(
          IERC20Minimal(address(tokens[0])),
          IERC20Minimal(address(tokens[1])),
          0,
          60,
          hooks
      );
      id = keccak256(abi.encode(key));
    }

    function generateHookAddress(Hooks.Calls memory calls) public pure returns (address) {
        uint256 callsBitmap = 0;
        if (calls.beforeInitialize != false) callsBitmap = callsBitmap | Hooks.BEFORE_INITIALIZE_FLAG;
        if (calls.afterInitialize != false) callsBitmap = callsBitmap | Hooks.AFTER_INITIALIZE_FLAG;
        if (calls.beforeModifyPosition != false) callsBitmap = callsBitmap | Hooks.BEFORE_MODIFY_POSITION_FLAG;
        if (calls.afterModifyPosition != false) callsBitmap = callsBitmap | Hooks.AFTER_MODIFY_POSITION_FLAG;
        if (calls.beforeSwap != false) callsBitmap = callsBitmap | Hooks.BEFORE_SWAP_FLAG;
        if (calls.afterSwap != false) callsBitmap = callsBitmap | Hooks.AFTER_SWAP_FLAG;
        if (calls.beforeDonate != false) callsBitmap = callsBitmap | Hooks.BEFORE_DONATE_FLAG;
        if (calls.afterDonate != false) callsBitmap = callsBitmap | Hooks.AFTER_DONATE_FLAG;
        return address(uint160(callsBitmap));
    }

    function createPool(
        PoolManager manager,
        IHooks hooks,
        uint160 sqrtPriceX96
    ) public returns (IPoolManager.PoolKey memory key, bytes32 id) {
        TestERC20[] memory tokens = deployTokens(2, 2**255);
        key = IPoolManager.PoolKey(
            IERC20Minimal(address(tokens[0])),
            IERC20Minimal(address(tokens[1])),
            0,
            1,
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
