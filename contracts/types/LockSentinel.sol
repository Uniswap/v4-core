// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {LockDataLibrary} from "../libraries/LockDataLibrary.sol";

/// @notice The LockSentinel holds global information for the LockData data structure which consists of the length and nonzeroDeltaCount.
/// @dev  The left most 128 bits holds the length, or total number of active lockers.
/// @dev The right most 128 bits hold the nonzeroDeltaCount, or total number of nonzero deltas over all active + completed lockers.
/// @dev Located in transient storage.
type LockSentinel is uint256;

using LockDataLibrary for LockSentinel global;
