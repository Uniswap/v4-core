import { createFixtureLoader } from 'ethereum-waffle'
import { Wallet } from 'ethers'
import { MAX_TICK, MIN_TICK } from './shared/constants'
import { expect } from './shared/expect'
import { GeomeanOracle, PoolManager, PoolModifyPositionTest, PoolSwapTest, TestERC20 } from '../typechain'
import hre, { ethers } from 'hardhat'
import { tokensFixture } from './shared/fixtures'
import { createHookMask, encodeSqrtPriceX96 } from './shared/utilities'

describe.only('GeomeanOracle', () => {
  let wallets: Wallet[]
  let oracle: GeomeanOracle
  let poolManager: PoolManager
  let token0: TestERC20
  let token1: TestERC20

  /**
   * We are using hardhat_setCode to deploy the geomean oracle, so we need to replace all the immutable references
   * @param poolManagerAddress the address of the pool manager, the only immutable of the geomean oracle
   */
  async function getDeployedGeomeanOracleCode(poolManagerAddress: string): Promise<string> {
    const artifact = await hre.artifacts.readArtifact('GeomeanOracle')
    const fullyQualifiedName = `${artifact.sourceName}:${artifact.contractName}`
    const debugArtifact = await hre.artifacts.getBuildInfo(fullyQualifiedName)
    const immutableReferences =
      debugArtifact?.output?.contracts?.[artifact.sourceName]?.[artifact.contractName]?.evm?.deployedBytecode
        ?.immutableReferences
    if (!immutableReferences) throw new Error('Could not find immutable references')
    if (Object.keys(immutableReferences).length !== 1) throw new Error('Unexpected immutable references length')
    const key = Object.keys(immutableReferences)[0]
    const refs = immutableReferences[key]
    let bytecode: string = artifact.deployedBytecode
    const paddedTo32Address = '0'.repeat(24) + poolManagerAddress.slice(2)
    for (const { start, length } of refs) {
      if (length !== 32) throw new Error('Unexpected immutable reference length')
      bytecode = bytecode.slice(0, start * 2 + 2) + paddedTo32Address + bytecode.slice(2 + start * 2 + length * 2)
    }
    return bytecode
  }

  const fixture = async ([wallet]: Wallet[]) => {
    const geomeanOracleFactory = await ethers.getContractFactory('GeomeanOracle')

    const poolManagerFactory = await ethers.getContractFactory('PoolManager')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const modifyPositionTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
    const tokens = await tokensFixture()
    const manager = (await poolManagerFactory.deploy()) as PoolManager

    const geomeanOracleHookAddress = createHookMask({
      beforeInitialize: true,
      afterInitialize: true,
      beforeModifyPosition: true,
      afterModifyPosition: false,
      beforeSwap: true,
      afterSwap: false,
      beforeDonate: false,
      afterDonate: false,
    })

    await hre.network.provider.send('hardhat_setCode', [
      geomeanOracleHookAddress,
      await getDeployedGeomeanOracleCode(manager.address),
    ])

    const geomeanOracle: GeomeanOracle = geomeanOracleFactory.attach(geomeanOracleHookAddress) as GeomeanOracle

    const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
    const modifyPositionTest = (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest

    for (const token of [tokens.token0, tokens.token1]) {
      for (const spender of [swapTest, modifyPositionTest]) {
        await token.connect(wallet).approve(spender.address, ethers.constants.MaxUint256)
      }
    }

    return {
      manager,
      swapTest,
      modifyPositionTest,
      tokens,
      geomeanOracle,
    }
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    wallets = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader(wallets)
  })

  beforeEach('deploy oracle', async () => {
    ;({
      geomeanOracle: oracle,
      manager: poolManager,
      tokens: { token0, token1 },
    } = await loadFixture(fixture))
  })

  describe('#beforeInitialize', async () => {
    // failing because of immutable not being set
    it('allows initialize of free max range pool', async () => {
      await poolManager.initialize(
        {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: oracle.address,
          tickSpacing: MAX_TICK,
        },
        encodeSqrtPriceX96(1, 1)
      )
    })

    it('reverts if pool has fee', async () => {
      await expect(
        poolManager.initialize(
          {
            token0: token0.address,
            token1: token1.address,
            fee: 1,
            hooks: oracle.address,
            tickSpacing: MAX_TICK,
          },
          encodeSqrtPriceX96(1, 1)
        )
      ).to.be.revertedWith('') // OraclePoolMustBeFreeFullRange()
    })

    it('reverts if pool has non-max tickspacing', async () => {
      await expect(
        poolManager.initialize(
          {
            token0: token0.address,
            token1: token1.address,
            fee: 0,
            hooks: oracle.address,
            tickSpacing: MIN_TICK,
          },
          encodeSqrtPriceX96(1, 1)
        )
      ).to.be.revertedWith('') // OraclePoolMustBeFreeFullRange()
    })
  })
})
