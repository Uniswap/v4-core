methods {
    function extsload(bytes32 slot) external returns (bytes32) => NONDET DELETE;
    function extsload(bytes32[] slots) external returns (bytes32[] memory) => ArbBytes32(slots) DELETE;
    function extsload(bytes32 startSlot, uint256 nSlots) external returns (bytes32[] memory) => ArbNBytes32(startSlot, nSlots) DELETE;
    function exttload(bytes32[] slots) external returns (bytes32[] memory) => ArbBytes32(slots) DELETE;

    function PoolGetters.getSqrtPriceX96(PoolManager.PoolId poolId) external returns (uint160) envfree;
    function PoolGetters.getTick(PoolManager.PoolId poolId) external returns (int24) envfree;
    function PoolGetters.getProtocolFee(PoolManager.PoolId poolId) external returns (uint24) envfree;
    function PoolGetters.getLpFee(PoolManager.PoolId poolId) external returns (uint24) envfree;
    function PoolGetters.getLiquidity(PoolManager.PoolId poolId) external returns (uint128) envfree;
    function PoolGetters.getPositionLiquidity(PoolManager.PoolId poolId, bytes32 positionId) external returns (uint128) envfree;
    function PoolGetters.getTickLiquidity(PoolManager.PoolId poolId, int24 tick) external returns (uint128, int128) envfree;
    function PoolGetters._getSlot0(PoolManager.PoolId poolId) internal returns (bytes32) => getSlot0Direct(poolId);
}

/// Returns an arbitrary bytes32 array with the same length as the slots input array.
function ArbBytes32(bytes32[] slots) returns bytes32[] {
    bytes32[] data;
    require data.length == slots.length;
    return data;
}

/// Returns an arbitrary bytes32 array of length nSlots.
function ArbNBytes32(bytes32 startSlot, uint256 nSlots) returns bytes32[] {
    bytes32[] data;
    require data.length == nSlots;
    return data;
}

/// Getters of the pool state using direct storage access.
function getTickLiquidityExt(PoolManager.PoolId poolId, int24 tick) returns (uint128,int128) {
    return (PoolManager._pools[poolId].ticks[tick].liquidityGross, PoolManager._pools[poolId].ticks[tick].liquidityNet);
}

function getActiveLiquidity(PoolManager.PoolId poolId) returns uint128 {
    return PoolManager._pools[poolId].liquidity;
}

function getPositionLiquidityExt(PoolManager.PoolId poolId, bytes32 positionId) returns uint128 {
    return PoolManager._pools[poolId].positions[positionId].liquidity;
}

function getSlot0Direct(PoolManager.PoolId poolId) returns bytes32 {
    return PoolManager._pools[poolId].slot0;
}
