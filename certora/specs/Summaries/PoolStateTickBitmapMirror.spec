/// Mirror of PoolManager._pools[id].tickBitmap:
/// mirror the storage of ticks in order to use in TickBitmap.nextInitializedTickWithinOneWord.

methods {
    function TickBitmap.nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage,  /// "self" is replaced with storage mirror
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal returns (int24,bool) => nextInitializedTickCVL(tick,tickSpacing,lte);

    function TickBitmap.flipTick(
        mapping(int16 => uint256) storage,  /// "self" is replaced with storage mirror
        int24 tick,
        int24 tickSpacing
    ) internal => flipTickCVL(tick, tickSpacing);
}

hook Sload uint256 tickBitmap PoolManager._pools[KEY PoolManager.PoolId id].tickBitmap[KEY int16 word] {
    require tickBitmap == tickBitMap_mirror[id][word];
}

hook Sstore PoolManager._pools[KEY PoolManager.PoolId id].tickBitmap[KEY int16 word] uint256 tickBitmap (uint256 old_value) {
    require old_value == tickBitMap_mirror[id][word];
    tickBitMap_mirror[id][word] = tickBitmap;
}

/// Is persistent because it mirrors the PoolManager storage.
/// Use this poolId in a rule when the isTickInitialized ghost value is important. 
/// WARNING: only applicable when the rule concerns a single poolId!
persistent ghost PoolManager.PoolId bitmapPoolId;
/// We define the next tick returned by the nextInitializedTickCVL() as a ghost, so we could reason about it before the function call.
persistent ghost int24 nextTickGhost;
/// Mapping (pool => tick => is tick initialized)
persistent ghost mapping(PoolManager.PoolId => mapping(int24 => bool)) isTickInitialized {
    init_state axiom forall PoolManager.PoolId poolId. forall int24 tick. !isTickInitialized[poolId][tick];
    /// Out-of-bounds ticks are never initialized.
    axiom forall PoolManager.PoolId poolId. forall int24 tick. !isValidTick(tick) => !isTickInitialized[poolId][tick];
}

/// storage mirror of PoolManager._pools[id].tickBitmap
/// Is persistent because it mirrors the PoolManager storage.
persistent ghost mapping(PoolManager.PoolId => mapping(int16 => uint256)) tickBitMap_mirror {
    init_state axiom forall PoolManager.PoolId poolId. forall int16 word. tickBitMap_mirror[poolId][word] == 0;
}

function nextInitializedTickCVL(int24 tick, int24 tickSpacing, bool lte) returns (int24, bool) {
    int24 nextTick = nextTickGhost;
    havoc nextTickGhost;
    require lte 
        ? (nextTick <= tick && tick - nextTick <= 256 * tickSpacing)
        : (nextTick > tick && nextTick - tick <= 256 * tickSpacing);
    require forall int24 innerTick. ( lte 
        ? innerTick > nextTick && innerTick <= tick 
        : innerTick < nextTick && innerTick > tick
    ) => !isTickInitialized[bitmapPoolId][innerTick];
    return (nextTick, isTickInitialized[bitmapPoolId][nextTick]);
}

function flipTickCVL(int24 tick, int24 tickSpacing) {
    /// Only aligned ticks are allowed.
    require (tickSpacing > 0 && tick % tickSpacing == 0);
    isTickInitialized[bitmapPoolId][tick] = !isTickInitialized[bitmapPoolId][tick];
}

function getTickBitmapDirect(PoolManager.PoolId poolId, int16 tick) returns uint256 {
    return PoolManager._pools[poolId].tickBitmap[tick];
}

/// Witness rule for tickBitMap storage mirror change.
rule tickBitMap_mirror_satisfy_store(PoolManager.PoolId id, int16 word) {
    uint256 bit_before = tickBitMap_mirror[id][word];
    uint256 bit_storage_before = getTickBitmapDirect(id, word);
        env e;
        calldataarg args;
        modifyLiquidity(e, args);
    uint256 bit_after = tickBitMap_mirror[id][word];
    uint256 bit_storage_after = getTickBitmapDirect(id, word);

    satisfy bit_before != bit_after;
    assert bit_before != bit_after => 
        bit_storage_after == bit_after && bit_storage_before == bit_before;
}
