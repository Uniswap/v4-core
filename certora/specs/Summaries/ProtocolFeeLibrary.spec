methods {
    function ProtocolFeeLibrary.calculateSwapFee(uint16 self, uint24 lpFee) internal returns (uint24) => swapFeeGhost(self, lpFee);
    function ProtocolFeeLibrary.isValidProtocolFee(uint24 self) internal returns (bool) => isValidProtocolFee(self);
}

definition PIPS() returns uint24 = 1000000;
definition MAX_LP_FEE() returns uint24 = PIPS();
definition MAX_PROTOCOL_FEE() returns uint16 = 1000;
definition MAX_PROTOCOL_FEE_24() returns uint24 = 1000;

function isValidProtocolFee(uint24 self) returns bool {
    return (self >> 12 <= MAX_PROTOCOL_FEE_24()) && (self & 0xFFF) <= MAX_PROTOCOL_FEE_24();
}

ghost swapFeeGhost(uint16,uint24) returns uint24 {
    axiom forall uint16 self. forall uint24 lpFee.
        (self <= MAX_PROTOCOL_FEE() && lpFee <= MAX_LP_FEE()) =>
        to_mathint(swapFeeGhost(self, lpFee)) >= to_mathint(self) &&
        swapFeeGhost(self, lpFee) <= PIPS();
}
