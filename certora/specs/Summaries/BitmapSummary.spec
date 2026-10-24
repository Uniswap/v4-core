/// Least significant bit
persistent ghost LSB(uint256) returns uint8 {
    axiom forall uint256 x. x >= (1 << LSB(x));
    axiom forall uint256 x. x % (1 << LSB(x)) == 0;
}

/// Most significant bit
persistent ghost MSB(uint256) returns uint8 {
    axiom forall uint256 x. x >= (1 << MSB(x));
    axiom forall uint256 x. to_mathint(1 << (MSB(x))) > x/2;
    axiom forall uint256 x. MSB(x) >= LSB(x);
}
