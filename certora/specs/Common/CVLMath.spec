function divUpCVL(uint256 x, uint256 y) returns uint256 {
    assert y !=0, "divUp error: cannot divide by zero";
    return require_uint256((x + y - 1) / y);
}

function mulDivDownCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    assert z !=0, "mulDivDown error: cannot divide by zero";
    return require_uint256(x * y / z);
}

function mulDivUpCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    assert z !=0, "mulDivDown error: cannot divide by zero";
    return require_uint256((x * y + z - 1) / z);
}

function mulDivDownCVL_no_div(uint256 x, uint256 y, uint256 z) returns uint256 {
    uint256 res;
    assert z != 0, "mulDivDown error: cannot divide by zero";
    mathint xy = x * y;
    mathint fz = res * z;

    require xy >= fz;
    require fz + z > xy;
    return res; 
}