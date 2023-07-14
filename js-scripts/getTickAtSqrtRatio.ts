// TODO: once hardhat is gone, js-scripts can go inside test folder

import Decimal from 'decimal.js'
import { ethers } from 'ethers';

const sqrtRatio: string = process.argv[2];
const jsResult = new Decimal(sqrtRatio).div(new Decimal(2).pow(96)).pow(2).log(1.0001).floor().toFixed(0)
process.stdout.write(ethers.utils.defaultAbiCoder.encode(['int256'], [jsResult]));
