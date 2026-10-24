/// A summary for the Slot0 library, which extracts the 4 data elements of the pool
/// from the bytes32 slot.
/// The verification of the library is found in specs/Libraries/Slot0Test.
/// The summary is implemented using persistent mappings that mock the bit masking.

methods {
    /// Getters
    function Slot0Library.sqrtPriceX96(PoolManager.Slot0 slot0) internal returns (uint160) => getSlotSqrtPriceX96CVL(slot0);
    function Slot0Library.tick(PoolManager.Slot0 slot0) internal returns (int24) => getSlotTickCVL(slot0);
    function Slot0Library.protocolFee(PoolManager.Slot0 slot0) internal returns (uint24) => getSlotProtocolFeeCVL(slot0);
    function Slot0Library.lpFee(PoolManager.Slot0 slot0) internal returns (uint24) => getSlotLPFeeCVL(slot0);

    /// Setters
    function Slot0Library.setSqrtPriceX96(PoolManager.Slot0 slot0, uint160 _sqrtPriceX96) internal returns (PoolManager.Slot0)
        => setSlotSqrtPriceX96(slot0, _sqrtPriceX96);
    function Slot0Library.setTick(PoolManager.Slot0 slot0, int24 _tick) internal returns (PoolManager.Slot0)
        => setSlotTick(slot0, _tick);
    function Slot0Library.setProtocolFee(PoolManager.Slot0 slot0, uint24 _protocolFee) internal returns (PoolManager.Slot0)
        => setSlotProtocolFee(slot0, _protocolFee);
    function Slot0Library.setLpFee(PoolManager.Slot0 slot0, uint24 _lpFee) internal returns (PoolManager.Slot0)
        => setSlotLPFee(slot0, _lpFee);

    /// Wrapper
    function PoolGetters.slot0Wrap(bytes32) external returns (PoolManager.Slot0) envfree;
    function PoolGetters.slot0Unwrap(PoolManager.Slot0) external returns (bytes32) envfree;
}

definition NULL_SLOT() returns bytes32 = to_bytes32(0);

/// Conversions from slot0 (bytes32) to parts:
persistent ghost slotSqrtPriceX96CVL(bytes32) returns uint160 {axiom slotSqrtPriceX96CVL(NULL_SLOT()) == 0;}
persistent ghost slotTickCVL(bytes32) returns int24 {axiom slotTickCVL(NULL_SLOT()) == 0;}
persistent ghost slotProtocolFeeCVL(bytes32) returns uint24 {axiom slotProtocolFeeCVL(NULL_SLOT()) == 0;}
persistent ghost slotLPFeeCVL(bytes32) returns uint24 {axiom slotLPFeeCVL(NULL_SLOT()) == 0;}

function getSlotSqrtPriceX96CVL(PoolManager.Slot0 slot0) returns uint160 {
    return slotSqrtPriceX96CVL(PoolGetters.slot0Unwrap(slot0));
}

function getSlotTickCVL(PoolManager.Slot0 slot0) returns int24 {
    return slotTickCVL(PoolGetters.slot0Unwrap(slot0));
}

function getSlotProtocolFeeCVL(PoolManager.Slot0 slot0) returns uint24 {
    return slotProtocolFeeCVL(PoolGetters.slot0Unwrap(slot0));
}

function getSlotLPFeeCVL(PoolManager.Slot0 slot0) returns uint24 {
    return slotLPFeeCVL(PoolGetters.slot0Unwrap(slot0));
}

function setSlotSqrtPriceX96(PoolManager.Slot0 slot0, uint160 _sqrtPriceX96) returns PoolManager.Slot0 {
    bytes32 newSlot;
    bytes32 oldSlot = PoolGetters.slot0Unwrap(slot0);
    require slotSqrtPriceX96CVL(newSlot) == _sqrtPriceX96;
    require slotTickCVL(newSlot) == slotTickCVL(oldSlot);
    require slotProtocolFeeCVL(newSlot) == slotProtocolFeeCVL(oldSlot);
    require slotLPFeeCVL(newSlot) == slotLPFeeCVL(oldSlot);
    return PoolGetters.slot0Wrap(newSlot);
}

function setSlotTick(PoolManager.Slot0 slot0, int24 _tick) returns PoolManager.Slot0 {
    bytes32 newSlot;
    bytes32 oldSlot = PoolGetters.slot0Unwrap(slot0);
    require slotSqrtPriceX96CVL(newSlot) == slotSqrtPriceX96CVL(oldSlot);
    require slotTickCVL(newSlot) == _tick;
    require slotProtocolFeeCVL(newSlot) == slotProtocolFeeCVL(oldSlot);
    require slotLPFeeCVL(newSlot) == slotLPFeeCVL(oldSlot);
    return PoolGetters.slot0Wrap(newSlot);
}

function setSlotProtocolFee(PoolManager.Slot0 slot0, uint24 _protocolFee) returns PoolManager.Slot0 {
    bytes32 newSlot;
    bytes32 oldSlot = PoolGetters.slot0Unwrap(slot0);
    require slotSqrtPriceX96CVL(newSlot) == slotSqrtPriceX96CVL(oldSlot);
    require slotTickCVL(newSlot) == slotTickCVL(oldSlot);
    require slotProtocolFeeCVL(newSlot) == _protocolFee;
    require slotLPFeeCVL(newSlot) == slotLPFeeCVL(oldSlot); 
    return PoolGetters.slot0Wrap(newSlot);
}

function setSlotLPFee(PoolManager.Slot0 slot0, uint24 _lpFee) returns PoolManager.Slot0 {
    bytes32 newSlot;
    bytes32 oldSlot = PoolGetters.slot0Unwrap(slot0);
    require slotSqrtPriceX96CVL(newSlot) == slotSqrtPriceX96CVL(oldSlot);
    require slotTickCVL(newSlot) == slotTickCVL(oldSlot);
    require slotProtocolFeeCVL(newSlot) == slotProtocolFeeCVL(oldSlot);
    require slotLPFeeCVL(newSlot) == _lpFee;
    return PoolGetters.slot0Wrap(newSlot);
}

