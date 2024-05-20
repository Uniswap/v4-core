import Decimal from 'decimal.js'
import { ethers } from 'ethers'

// Run this script solo by: npm run forge-test-mulDiv "a b denominator" 
// Read command line arguments
const args = process.argv[2].split(' ');
const a = args[0];
const b = args[1];
const denominator = args[2];

// Perform mulDiv operation using JSBI
const result = new Decimal(a).mul(b).div(denominator).toFixed(0)

// Optionally, you can encode the result using ethers.js if needed
process.stdout.write(ethers.utils.defaultAbiCoder.encode(['uint256'], [result.toString()]))
