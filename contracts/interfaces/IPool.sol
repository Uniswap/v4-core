// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IPoolImmutables} from './pool/IPoolImmutables.sol';
import {IPoolState} from './pool/IPoolState.sol';
import {IPoolDerivedState} from './pool/IPoolDerivedState.sol';
import {IPoolActions} from './pool/IPoolActions.sol';
import {IPoolOwnerActions} from './pool/IPoolOwnerActions.sol';
import {IPoolEvents} from './pool/IPoolEvents.sol';

/// @title The full interface for a Pool
/// @notice A Uniswap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IPool is IPoolImmutables, IPoolState, IPoolDerivedState, IPoolActions, IPoolOwnerActions, IPoolEvents {

}
