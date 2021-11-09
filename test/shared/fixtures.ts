import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import {
  UniswapV3Factory,
  MockTimeUniswapV3PoolDeployer,
  TestUniswapV3Router,
  TestUniswapV3Callee,
  UniswapV3Pool,
  MockTimeUniswapV3Pool,
  TestERC20,
} from '../../typechain'

import { Fixture } from 'ethereum-waffle'
import { getCreate2Address } from './utilities'

interface PoolImplementationFixture {
  pool: UniswapV3Pool
  mockTimePool: MockTimeUniswapV3Pool
}

export async function poolImplementationFixture(): Promise<PoolImplementationFixture> {
  const poolFactory = await ethers.getContractFactory('UniswapV3Pool')
  const pool = (await poolFactory.deploy()) as UniswapV3Pool
  const mockTimePoolFactory = await ethers.getContractFactory('MockTimeUniswapV3Pool')
  const mockTimePool = (await mockTimePoolFactory.deploy()) as MockTimeUniswapV3Pool
  return { pool, mockTimePool }
}

interface FactoryFixture extends PoolImplementationFixture {
  factory: UniswapV3Factory
}

export async function factoryFixture(): Promise<FactoryFixture> {
  const { mockTimePool, pool } = await poolImplementationFixture()
  const factoryFactory = await ethers.getContractFactory('UniswapV3Factory')
  const factory = (await factoryFactory.deploy(pool.address)) as UniswapV3Factory
  return { factory, pool, mockTimePool }
}

interface TokensFixture {
  token0: TestERC20
  token1: TestERC20
  token2: TestERC20
}

async function tokensFixture(): Promise<TokensFixture> {
  const tokenFactory = await ethers.getContractFactory('TestERC20')
  const tokenA = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestERC20
  const tokenB = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestERC20
  const tokenC = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestERC20

  const [token0, token1, token2] = [tokenA, tokenB, tokenC].sort((tokenA, tokenB) =>
    tokenA.address.toLowerCase() < tokenB.address.toLowerCase() ? -1 : 1
  )

  return { token0, token1, token2 }
}

type TokensAndFactoryFixture = FactoryFixture & TokensFixture

interface PoolFixture extends TokensAndFactoryFixture {
  swapTargetCallee: TestUniswapV3Callee
  swapTargetRouter: TestUniswapV3Router
  createPool(
    fee: number,
    tickSpacing: number,
    firstToken?: TestERC20,
    secondToken?: TestERC20
  ): Promise<MockTimeUniswapV3Pool>
}

export const TEST_POOL_START_TIME = 0

export const poolFixture: Fixture<PoolFixture> = async function (): Promise<PoolFixture> {
  const { factory, pool, mockTimePool } = await factoryFixture()
  const { token0, token1, token2 } = await tokensFixture()

  const MockTimeUniswapV3PoolDeployerFactory = await ethers.getContractFactory('MockTimeUniswapV3PoolDeployer')
  const MockTimeUniswapV3PoolFactory = await ethers.getContractFactory('MockTimeUniswapV3Pool')

  const mockTimePoolDeployer = (await MockTimeUniswapV3PoolDeployerFactory.deploy(
    mockTimePool.address
  )) as MockTimeUniswapV3PoolDeployer

  const calleeContractFactory = await ethers.getContractFactory('TestUniswapV3Callee')
  const routerContractFactory = await ethers.getContractFactory('TestUniswapV3Router')

  const swapTargetCallee = (await calleeContractFactory.deploy()) as TestUniswapV3Callee
  const swapTargetRouter = (await routerContractFactory.deploy()) as TestUniswapV3Router

  const poolProxyBytecode = (await ethers.getContractFactory('UniswapV3PoolProxy')).bytecode

  return {
    pool,
    mockTimePool,
    token0,
    token1,
    token2,
    factory,
    swapTargetCallee,
    swapTargetRouter,
    createPool: async (fee, tickSpacing, firstToken = token0, secondToken = token1) => {
      await mockTimePoolDeployer.createPool(factory.address, firstToken.address, secondToken.address, fee, tickSpacing)

      const poolAddress = getCreate2Address(
        mockTimePoolDeployer.address,
        [firstToken.address, secondToken.address],
        fee,
        poolProxyBytecode
      )

      // const receipt = await tx.wait()
      // const poolAddress = receipt.events?.[0].args?.pool as string
      return MockTimeUniswapV3PoolFactory.attach(poolAddress) as MockTimeUniswapV3Pool
    },
  }
}
