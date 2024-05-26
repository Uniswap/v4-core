import JSBI from 'jsbi'
import { ethers } from 'ethers'

// Run this script solo by: npm run forge-test-mulDiv "a,b,denominator" 
// Read command line arguments
const args = process.argv[2].split(',');
const a = JSBI.BigInt(args[0])
const b = JSBI.BigInt(args[1])
const denominator = JSBI.BigInt(args[2])

// Perform mulDiv operation
const result = JSBI.divide(JSBI.multiply(a, b), denominator)

// Check if result is greater than uint256Max
const uint256Max = JSBI.BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
if (JSBI.greaterThan(result, uint256Max)) {
    process.stdout.write(ethers.utils.defaultAbiCoder.encode(['bool', 'uint256'], [false, 0]));
} else {
    process.stdout.write(ethers.utils.defaultAbiCoder.encode(['bool', 'uint256'], [true, result.toString()]))
}

