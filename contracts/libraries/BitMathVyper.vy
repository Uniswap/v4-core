# @version ^0.3.3

@pure
@internal
def mostSignificantBit(v: uint256) -> uint8:
    assert v > 0
    x: uint256 = v
    r: uint256 = 0
    if (x >= shift(1, 128)):
        x = shift(x, -128)
        r = unsafe_add(r, 128)
    if (x >= shift(1, 64)):
        x = shift(x, -64)
        r = unsafe_add(r, 64)
    if (x >= shift(1, 32)):
        x = shift(x, -32)
        r = unsafe_add(r, 32)
    if (x >= shift(1, 16)):
        x = shift(x, -16)
        r = unsafe_add(r, 16)
    if (x >= shift(1, 8)):
        x = shift(x, -8)
        r = unsafe_add(r, 8)
    if (x >= shift(1, 4)):
        x = shift(x, -4)
        r = unsafe_add(r, 4)
    if (x >= shift(1, 2)):
        x = shift(x, -2)
        r = unsafe_add(r, 2)
    if (x >= 2):
        r = unsafe_add(r, 1)
    return convert(r, uint8)


@external
@view
def mostSignificantBitExternal(v: uint256) -> uint8:
    return self.mostSignificantBit(v)

@external
@view
def getGasCostOfMostSignificantBit(v: uint256) -> uint256:
    gasBefore: uint256 = msg.gas
    self.mostSignificantBit(v)
    return unsafe_sub(gasBefore, msg.gas)