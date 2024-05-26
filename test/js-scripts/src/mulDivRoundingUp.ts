import  JSBI  from 'jsbi';
import { ethers } from 'ethers'
import { FullMath } from '@uniswap/v3-sdk';

const args = process.argv[2].split(',');
const a = JSBI.BigInt(args[0])
const b = JSBI.BigInt(args[1])
const denominator = JSBI.BigInt(args[2])

const result = FullMath.mulDivRoundingUp(a, b, denominator);

// Check if result is greater than uint256Max
const uint256Max = JSBI.BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
if (JSBI.greaterThan(result, uint256Max)) {
    process.stdout.write(ethers.utils.defaultAbiCoder.encode(['bool', 'uint256'], [false, 0]));
} else {
    process.stdout.write(ethers.utils.defaultAbiCoder.encode(['bool', 'uint256'], [true, result.toString()]))
}
