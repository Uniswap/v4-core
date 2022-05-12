import { ethers } from 'hardhat'

export async function inOneBlock(timestamp: number, fn: () => void) {
  await ethers.provider.send('evm_setAutomine', [false])
  await fn()
  await ethers.provider.send('evm_setAutomine', [true])
  await ethers.provider.send('evm_mine', [timestamp])
}

export async function latestTimestamp(): Promise<number> {
  return (await ethers.provider.getBlock('latest')).timestamp
}

export async function setNextBlocktime(time: number) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [time])
}
