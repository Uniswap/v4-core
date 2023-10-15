import Decimal from 'decimal.js'
import { ethers } from 'ethers'

const tickArray = process.argv[2].split(',')
const resultsArray = []
for (let tick of tickArray) {
  const jsResult = new Decimal(1.0001).pow(tick).sqrt().mul(new Decimal(2).pow(96)).toFixed(0)
  resultsArray.push(jsResult)
}
process.stdout.write(ethers.utils.defaultAbiCoder.encode(['uint160[]'], [resultsArray]))
