// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ProtocolFees} from "../ProtocolFees.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {PoolId} from "../types/PoolId.sol";
import {Pool} from "../libraries/Pool.sol";

import "forge-std/console2.sol";

contract ProtocolFeesImplementation is ProtocolFees {

    mapping(uint256 => Pool.State) pools;

    constructor(uint256 _controllerGasLimit) ProtocolFees(_controllerGasLimit) {}

    function _getPool(PoolId) internal override view returns (Pool.State storage) {
        return pools[0];
    }

    function fetchProtocolFee(PoolKey memory key) public returns (bool, uint24) {
        console2.log("fetching 1");
        return ProtocolFees._fetchProtocolFee(key);
    }

    function updateProtocolFees(Currency currency, uint256 amount) public {
        ProtocolFees._updateProtocolFees(currency, amount);
    }
}