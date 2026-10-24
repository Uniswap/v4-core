/// The minimum value that can be returned from #getSqrtPriceAtTick.
definition MIN_SQRT_PRICE() returns uint160 = 4295128739;
/// The maximum value that can be returned from #getSqrtPriceAtTick.
definition MAX_SQRT_PRICE() returns uint160 = 1461446703485210103287273052203988822378723970342;
/// The sqrt ratio value for tick = 0
definition ZERO_TICK_SQRT_PRICE() returns uint160 = 79228162514264337593543950336; // (2**96)
/// The minimum tick that may be passed to #getSqrtPriceAtTick.
definition MIN_TICK() returns int24 = -887272;
/// The maximum tick that may be passed to #getSqrtPriceAtTick.
definition MAX_TICK() returns int24 = 887272;
/// The tick for sqrt ratio of Q96() = 2**96.
definition ONE_RATIO_TICK() returns int24 = 0;
/// (2**96)
definition Q96_256() returns uint256 = (1 << 96);
definition Q96_160() returns uint160 = (1 << 96);

definition isValidSqrt(uint160 sqrt) returns bool = sqrt >= MIN_SQRT_PRICE() && sqrt <= MAX_SQRT_PRICE();
definition isValidSqrtStrong(uint160 sqrt) returns bool = isValidSqrt(sqrt) && sqrt < MAX_SQRT_PRICE();
definition isValidTick(int24 tick) returns bool = tick >= MIN_TICK() && tick <= MAX_TICK();
definition isValidTickStrong(int24 tick) returns bool = isValidTick(tick) && tick < MAX_TICK();