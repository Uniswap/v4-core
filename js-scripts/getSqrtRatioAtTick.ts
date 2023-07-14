// TODO: once hardhat is gone, js-scripts can go inside test folder

import Decimal from 'decimal.js'
import { ethers } from 'ethers';

const tick = process.argv[2];
const jsResult = new Decimal(1.0001).pow(tick).sqrt().mul(new Decimal(2).pow(96)).toFixed(0)
process.stdout.write(ethers.utils.defaultAbiCoder.encode(['uint256'], [jsResult]));
