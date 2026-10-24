// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PoolIdLibrary, PoolKey, PoolId } from "src/types/PoolId.sol";
import { StateLibrary } from "src/libraries/StateLibrary.sol";
import { Position } from "src/libraries/Position.sol";
import { TransientStateLibrary } from "src/libraries/TransientStateLibrary.sol";
import { Slot0Library, Slot0 } from "src/types/Slot0.sol";
import { IPoolManager } from "src/interfaces/IPoolManager.sol";
import { Currency } from "src/types/Currency.sol";

contract PoolGetters {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IPoolManager private immutable manager;

    constructor(address _manager) {
        manager = IPoolManager(_manager);
    }

    function slot0Wrap(bytes32 _slot0) external pure returns (Slot0) {
        return Slot0.wrap(_slot0);
    }

    function slot0Unwrap(Slot0 _slot0) external pure returns (bytes32) {
        return Slot0.unwrap(_slot0);
    } 

    function toId(PoolKey memory poolKey) external pure returns (PoolId) {
        return PoolIdLibrary.toId(poolKey);
    }

    function _getSlot0(PoolId poolId) internal view returns (bytes32) {
        bytes32 stateSlot = StateLibrary._getPoolStateSlot(poolId);
        return manager.extsload(stateSlot);
    }

    function getSqrtPriceX96(PoolId poolId) external view returns (uint160) {
        Slot0 packed = Slot0.wrap(_getSlot0(poolId));
        return Slot0Library.sqrtPriceX96(packed);
    }

    function getTick(PoolId poolId) external view returns (int24 _tick) {
        Slot0 packed = Slot0.wrap(_getSlot0(poolId));
        return Slot0Library.tick(packed);
    }

    function getProtocolFee(PoolId poolId) external view returns (uint24 _protocolFee) {
        Slot0 packed = Slot0.wrap(_getSlot0(poolId));
        return Slot0Library.protocolFee(packed);
    }

    function getLpFee(PoolId poolId) external view returns (uint24 _lpFee) {
        Slot0 packed = Slot0.wrap(_getSlot0(poolId));
        return Slot0Library.lpFee(packed);
    }

    function getTickLiquidity(PoolId poolId, int24 tick) external view returns (uint128, int128) {
        return manager.getTickLiquidity(poolId, tick);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return manager.getLiquidity(poolId);
    }

    function getPositionLiquidity(PoolId poolId, bytes32 positionId) external view returns (uint128) {
        return manager.getPositionLiquidity(poolId, positionId);
    }

    function currencyDelta(address caller, Currency currency) external view returns (int256) {
        return manager.currencyDelta(caller, currency);
    }

    function isUnlocked() external view returns (bool) {
        return manager.isUnlocked();
    }

    function getNonzeroDeltaCount() external view returns (uint256) {
        return manager.getNonzeroDeltaCount();
    }

    function getPositionKey(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external pure returns (bytes32) {
        return Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
    }
}
