import "../Summaries/BitmapSummary.spec";

methods {
    function bitmap(int16) external returns (uint256) envfree;
    function flipTick() external envfree;
    function flipTickSol() external envfree;
    function differentTicks01() external returns (bool) envfree;
    function setNextInitializedTickWithinOneWord(bool) external envfree;
    function isInitialized0() external returns (bool) envfree;
    function isInitialized1() external returns (bool) envfree;
    function nextTickGTTick() external returns (bool) envfree;
    function tick0() external returns (int24) envfree;
    function tick1() external returns (int24) envfree;
    function tickSpacing0() external returns (int24) envfree;
    function tick1BetweenNextAndCurrent(bool) external returns (bool) envfree;
    function nextTick() external returns (int24) envfree;
    function nextInitialized() external returns (bool) envfree;
    function isNextInitialized() external returns (bool) envfree;
    function isValidTick() external returns (bool) envfree;
    function isValidTickSpacing() external returns (bool) envfree;
    function isAtLeastOneWord(bool lte) external returns (bool) envfree;
    function getBitPos(bool) external returns (uint8) envfree;
    function getBitPosNext() external returns (uint8) envfree;
    function getBitMapAtWord(bool lte) external returns (uint256) envfree;
    function getBitPosMask(bool, uint8) external returns (uint256) envfree;

    function setTick0(uint24,bool) external envfree;
    function setTickSpacing0(uint24) external envfree;
    function compress() external envfree;
    function compressSol() external envfree;
    function position() external envfree;
    function positionSol() external envfree;
    function getLSB(uint256) external returns (uint8) envfree;

    function BitMath.mostSignificantBit(uint256 x) internal returns (uint8) => MSB(x);
    function BitMath.leastSignificantBit(uint256 x) internal returns (uint8) => LSB(x);
}

use builtin rule sanity;

definition MAX_TICK_SPACING() returns mathint = 32767;

/// Prove without using summary for LSB()
/*rule getLSBMasking(uint256 x, uint8 bitPos) {
    uint256 mask = getBitPosMask(false, bitPos);
    uint256 masked = x & mask;
    uint8 lsb = getLSB(masked);

    assert x & (1 << lsb) !=0;
    assert lsb >= bitPos;
}*/

/// @title Equivalence between inline-assembly and Solidity implementation of compress()
rule compressEquivalence() {
    require isValidTick();
    require isValidTickSpacing();

    storage initState = lastStorage;

    compress@withrevert() at initState;
        bool revertedA = lastReverted;
        storage stateAssembly = lastStorage;

    compressSol@withrevert() at initState;
        bool revertedB = lastReverted;
        storage stateSol = lastStorage;

    assert revertedA <=> revertedB;
    assert stateAssembly[currentContract] == stateSol[currentContract];
}

/// @title Equivalence between inline-assembly and Solidity implementation of position()
rule positionEquivalence() {
    require isValidTick();
    require isValidTickSpacing();

    storage initState = lastStorage;

    position@withrevert() at initState;
        bool revertedA = lastReverted;
        storage stateAssembly = lastStorage;

    positionSol@withrevert() at initState;
        bool revertedB = lastReverted;
        storage stateSol = lastStorage;

    assert revertedA <=> revertedB;
    assert stateAssembly[currentContract] == stateSol[currentContract];
}

/// @title Equivalence between inline-assembly and Solidity implementation of flipTick()
rule flipTickEquivalence() {
    require isValidTick();
    require isValidTickSpacing();

    storage initState = lastStorage;

    flipTick@withrevert() at initState;
        bool revertedA = lastReverted;
        storage stateAssembly = lastStorage;

    flipTickSol@withrevert() at initState;
        bool revertedB = lastReverted;
        storage stateSol = lastStorage;

    assert revertedA <=> revertedB;
    assert stateAssembly[currentContract] == stateSol[currentContract];
}

/// @title Calling flipTick() negates the tick state (true <-> false).
rule flipTickIntegrityTest() {
    bool isInitialized_before = isInitialized0();
        flipTick();
    bool isInitialized_after = isInitialized0();

    assert isInitialized_after != isInitialized_before;
}

/// @title Calling flipTick() changes the state of the input tick only.
rule flipTickAffectsOnlyTickTest() {
    require differentTicks01();
    bool isInitialized_before = isInitialized1();
        flipTick();
    bool isInitialized_after = isInitialized1();

    assert isInitialized_after == isInitialized_before;
}

/// @title Formal version of test/libraries/TickBitmap.t.sol/test_fuzz_nextInitializedTickWithinOneWord
rule test_FV_nextInitializedTickWithinOneWord(bool lte) {
    // assume tick is at least one word inside type(int24).(max | min)
    require isAtLeastOneWord(lte);
    require isValidTickSpacing();
    require isValidTick();
    /// Under-approximation: can be replaced with any other valid value (rule should still pass).
    require to_mathint(tickSpacing0()) == 2 || to_mathint(tickSpacing0()) == 1;

    /// Returns the bit position of compressed(tick0, tickSpacing0) and the mask of the bit position.
    uint8 bitPos_ = getBitPos(lte);
    uint256 mask = getBitPosMask(lte, bitPos_);
    /// Calculate the masked bitmap
    uint256 self = getBitMapAtWord(lte);
    uint256 masked = self & mask;
    if(!lte) {
        /// Mask is all 1's from bitPos to the left.
        uint8 someBit;
        assert (someBit < bitPos_) => mask & (1 << someBit) == 0;
        /// See `getLSBMasking' rule.
        require self & (1 << LSB(masked)) !=0;
        require LSB(masked) >= bitPos_;
    }

    setNextInitializedTickWithinOneWord(lte);
    require tick1BetweenNextAndCurrent(lte);

    assert lte <=> !nextTickGTTick();
    // all the ticks between the input tick and the next tick should be uninitialized
    assert !isInitialized1();
    assert isNextInitialized() == nextInitialized();
}
