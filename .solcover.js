module.exports = {
  skipFiles: [
    'BitMathEchidnaTest.sol',
    'test/FullMathEchidnaTest.sol',
    'test/OracleEchidnaTest.sol',
    'test/SqrtPriceMathEchidnaTest.sol',
    'test/SwapMathEchidnaTest.sol',
    'test/TickBitmapEchidnaTest.sol',
    'test/TickEchidnaTest.sol',
    'test/TickMathEchidnaTest.sol',
    'test/TickOverflowSafetyEchidnaTest.so',
    'test/UnsafeMathEchidnaTest.sol',
  ],
    mocha: {
        grep: "@skip-on-coverage", // Find everything with this tag
        invert: true               // Run the grep's inverse set.
    }
};
