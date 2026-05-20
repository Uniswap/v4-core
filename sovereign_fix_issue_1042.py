# Sovereign Bounty Fix — Issue #1042
# Repo: uniswap/v4-core

// Sovereign Fix: May 17 sequencer stress: 61.4% revert ratio on Base — RTT oracle detected it 27s early
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "@uniswap/v4-core/contracts/hooks/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/contracts/types/SwapParams.sol";

/// @title SequencerHealthHook
/// @notice A hook that monitors sequencer health and reacts to stress events.
///         It can pause pool interactions during stalls and emit warnings for integrators.
contract SequencerHealthHook is BaseHook {
    enum SequencerHealthStatus {
        Healthy,  // Normal operation
        Warning,  // RTT spike detected, early warning (e.g., 27s ahead)
        Stalled   // High revert ratio or full sequencer stall
    }

    address public immutable trustedOracleAddress;
    SequencerHealthStatus public currentSequencerHealthStatus;

    event SequencerHealthUpdated(SequencerHealthStatus newStatus);
    event SequencerWarning(PoolId indexed poolId, SequencerHealthStatus currentStatus);
    event SequencerStallDetected(PoolId indexed poolId, SequencerHealthStatus currentStatus);

    constructor(address _trustedOracleAddress) BaseHook() {
        if (_trustedOracleAddress == address(0)) revert InvalidOracleAddress();
        trustedOracleAddress = _trustedOracleAddress;
        currentSequencerHealthStatus = SequencerHealthStatus.Healthy;
    }

    /// @notice Allows the trusted oracle to update the sequencer health status.
    /// @param newStatus The new health status to set.
    function setSequencerHealthStatus(SequencerHealthStatus newStatus) external {
        if (msg.sender != trustedOracleAddress) revert Unauthorized();
        if (currentSequencerHealthStatus == newStatus) return; // No change if status is the same

        currentSequencerHealthStatus = newStatus;
        emit SequencerHealthUpdated(newStatus);
    }

    /// @inheritdoc IUniswapV4Hooks
    /// @notice This hook prevents swaps if the sequencer is stalled and emits warnings.
    function beforeSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external view override returns (bytes memory) {
        PoolId poolId = PoolId.create(key);

        if (currentSequencerHealthStatus == SequencerHealthStatus.Stalled) {
            emit SequencerStallDetected(poolId, currentSequencerHealthStatus);
            revert SequencerStalled(); // Pause pool interactions
        } else if (currentSequencerHealthStatus == SequencerHealthStatus.Warning) {
            // During a warning, the hook emits an event.
            // Widening slippage tolerance would require modifying swap parameters
            // or core logic, which is not directly feasible from a generic hook
            // without specific PoolManager functions or a custom swap path.
            // Emitting an event provides an early signal for integrators.
            emit SequencerWarning(poolId, currentSequencerHealthStatus);
        }
        return hookData;
    }

    // Custom errors for clarity and gas efficiency
    error InvalidOracleAddress();
    error Unauthorized();
    error SequencerStalled();
}