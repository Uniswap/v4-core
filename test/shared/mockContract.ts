import { FormatTypes, Interface } from 'ethers/lib/utils'
import hre, { ethers } from 'hardhat'
import { MockContract } from '../../typechain'

export interface MockedContract {
  address: string
  called: (fn: string) => Promise<boolean>
  calledOnce: (fn: string) => Promise<boolean>
  calledWith: (fn: string, params: any[]) => Promise<boolean>
}

export const deployMockContract = async (
  contractInterface: Interface,
  address: string,
  implAddress?: string
): Promise<MockedContract> => {
  await setCode(address, 'MockContract')

  const contractMock = (await ethers.getContractFactory('MockContract')).attach(address) as MockContract

  if (implAddress) {
    contractMock.setImplementation(implAddress)
  }

  return {
    address,
    called: async (fn: string): Promise<boolean> => {
      return (await contractMock.timesCalled(contractInterface.getFunction(fn).format(FormatTypes.sighash))).gt(0)
    },
    calledOnce: async (fn: string): Promise<boolean> => {
      return (await contractMock.timesCalled(contractInterface.getFunction(fn).format(FormatTypes.sighash))).eq(1)
    },
    calledWith: async (fn: string, params: any[]): Promise<boolean> => {
      // Drop fn selector, keep 0x prefix so ethers interprets as byte string
      const paramsBytes = '0x' + contractInterface.encodeFunctionData(fn, params).slice(10)
      return contractMock.calledWith(contractInterface.getFunction(fn).format(FormatTypes.sighash), paramsBytes)
    },
  }
}

export const setCode = async (address: string, artifactName: string) => {
  await hre.network.provider.send('hardhat_setCode', [
    address,
    (await hre.artifacts.readArtifact(artifactName)).deployedBytecode,
  ])
}
