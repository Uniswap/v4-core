import { ethers } from 'ethers'
import fs from 'fs';

// Run this script solo by: npm run forge-test-mulDiv "a b denominator" 
// Read command line arguments
const args = process.argv[2].split(' ');
const a = args[0]
const b = args[1]
const denominator = args[2]
// Append new values to the array
let existingValues = [];

try {
    const data = fs.readFileSync('fuzzValues.json', 'utf-8');
    existingValues = JSON.parse(data);
} catch (error) {
    // Handle the case where the file doesn't exist or is empty
}

existingValues.push({ a, b, denominator });

// Write updated array back to JSON file
fs.writeFileSync('fuzzValues.json', JSON.stringify(existingValues, null, 2)); 
