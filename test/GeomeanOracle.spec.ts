import { createFixtureLoader } from 'ethereum-waffle'
import { Wallet } from 'ethers'
import hre, { ethers } from 'hardhat'
import { MockTimeGeomeanOracle, PoolManager, PoolModifyPositionTest, PoolSwapTest, TestERC20 } from '../typechain'
import { MAX_TICK_SPACING } from './shared/constants'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import { createHookMask, encodeSqrtPriceX96, getMaxTick, getMinTick } from './shared/utilities'

describe('GeomeanOracle', () => {
  let wallets: Wallet[]
  let oracle: MockTimeGeomeanOracle
  let poolManager: PoolManager
  let swapTest: PoolSwapTest
  let modifyPositionTest: PoolModifyPositionTest
  let token0: TestERC20
  let token1: TestERC20

  /**
   * We are using hardhat_setCode to deploy the geomean oracle, so we need to replace all the immutable references
   * @param poolManagerAddress the address of the pool manager, the only immutable of the geomean oracle
   */
  async function getDeployedGeomeanOracleCode(poolManagerAddress: string): Promise<string> {
    const artifact = await hre.artifacts.readArtifact('MockTimeGeomeanOracle')
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
    const geomeanOracleFactory = await ethers.getContractFactory('MockTimeGeomeanOracle')

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

    const geomeanOracle: MockTimeGeomeanOracle = geomeanOracleFactory.attach(
      geomeanOracleHookAddress
    ) as MockTimeGeomeanOracle

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

  let poolKey: {
    token0: string
    token1: string
    fee: number
    tickSpacing: number
    hooks: string
  }

  beforeEach('deploy oracle', async () => {
    ;({
      geomeanOracle: oracle,
      manager: poolManager,
      tokens: { token0, token1 },
      swapTest,
      modifyPositionTest,
    } = await loadFixture(fixture))
    poolKey = {
      token0: token0.address,
      token1: token1.address,
      fee: 0,
      hooks: oracle.address,
      tickSpacing: MAX_TICK_SPACING,
    }
    await oracle.setTime(1)
  })

  let snapshotId: string

  beforeEach('check the pool is not initialized', async () => {
    const { sqrtPriceX96 } = await poolManager.getSlot0(poolKey)
    expect(sqrtPriceX96, 'pool is not initialized').to.eq(0)
    // it seems like the waffle fixture is not working correctly (perhaps due to hardhat_setCode), and if we don't do this and revert in afterEach, the pool is already initialized
    snapshotId = await hre.network.provider.send('evm_snapshot')
  })

  afterEach('revert', async () => {
    // see the beforeEach hook
    await hre.network.provider.send('evm_revert', [snapshotId])
  })

  describe('#beforeInitialize', async () => {
    it('allows initialize of free max range pool', async () => {
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
    })

    it('reverts if pool has fee', async () => {
      await expect(
        poolManager.initialize(
          {
            token0: token0.address,
            token1: token1.address,
            fee: 1,
            hooks: oracle.address,
            tickSpacing: MAX_TICK_SPACING,
          },
          encodeSqrtPriceX96(1, 1)
        )
      ).to.be.revertedWith('OnlyOneOraclePoolAllowed()')
    })

    it('reverts if pool has non-max tickspacing', async () => {
      await expect(
        poolManager.initialize(
          {
            token0: token0.address,
            token1: token1.address,
            fee: 0,
            hooks: oracle.address,
            tickSpacing: 60,
          },
          encodeSqrtPriceX96(1, 1)
        )
      ).to.be.revertedWith('OnlyOneOraclePoolAllowed()')
    })
  })

  describe('#afterInitialize', async () => {
    it('initializes the oracle state', async () => {
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(2, 1))
      const { index, cardinality, cardinalityNext } = await oracle.getState(poolKey)
      expect(index).to.eq(0)
      expect(cardinality).to.eq(1)
      expect(cardinalityNext).to.eq(1)
    })
    it('initializes the observations array index 0', async () => {
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(2, 1))
      const { tickCumulative, secondsPerLiquidityCumulativeX128, blockTimestamp, initialized } =
        await oracle.getObservation(poolKey, 0)
      expect(initialized).to.be.true
      expect(blockTimestamp, 'timestamp').to.eq(1)
      expect(tickCumulative, 'cumulative tick').to.eq(0)
      expect(secondsPerLiquidityCumulativeX128, 'seconds per liquidity').to.eq(0)
    })
    it('observe of 0', async () => {
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(2, 1))
      const {
        tickCumulatives: [tickCumulative],
        secondsPerLiquidityCumulativeX128s: [secondsPerLiquidityCumulativeX128],
      } = await oracle.observe(poolKey, [0])
      expect(tickCumulative).to.eq(0)
      expect(secondsPerLiquidityCumulativeX128).to.eq(0)
    })
  })

  describe('#beforeModifyPosition', async () => {
    beforeEach('initialize the pool', async () => {
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(2, 1))
    })

    it('modifyPosition cannot be called with tick ranges other than min/max tick', async () => {
      await expect(
        modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -MAX_TICK_SPACING,
          tickUpper: MAX_TICK_SPACING,
          liquidityDelta: 1000,
        })
      ).to.be.revertedWith('OraclePositionsMustBeFullRange()')
      await expect(
        modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(MAX_TICK_SPACING),
          tickUpper: MAX_TICK_SPACING,
          liquidityDelta: 1000,
        })
      ).to.be.revertedWith('OraclePositionsMustBeFullRange()')
      await expect(
        modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -MAX_TICK_SPACING,
          tickUpper: getMaxTick(MAX_TICK_SPACING),
          liquidityDelta: 1000,
        })
      ).to.be.revertedWith('OraclePositionsMustBeFullRange()')
    })

    it('modifyPosition with no time change writes no observations', async () => {
      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(MAX_TICK_SPACING),
        tickUpper: getMaxTick(MAX_TICK_SPACING),
        liquidityDelta: 1000,
      })
      const { index, cardinality, cardinalityNext } = await oracle.getState(poolKey)
      expect(index).to.eq(0)
      expect(cardinality).to.eq(1)
      expect(cardinalityNext).to.eq(1)

      const { tickCumulative, secondsPerLiquidityCumulativeX128, blockTimestamp, initialized } =
        await oracle.getObservation(poolKey, 0)
      expect(initialized).to.be.true
      expect(blockTimestamp, 'timestamp').to.eq(1)
      expect(tickCumulative, 'cumulative tick').to.eq(0)
      expect(secondsPerLiquidityCumulativeX128, 'seconds per liquidity').to.eq(0)
    })

    it('modifyPosition with time change writes an observation', async () => {
      await oracle.setTime(3) // advance 2 seconds
      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(MAX_TICK_SPACING),
        tickUpper: getMaxTick(MAX_TICK_SPACING),
        liquidityDelta: 1000,
      })
      const { index, cardinality, cardinalityNext } = await oracle.getState(poolKey)
      expect(index).to.eq(0)
      expect(cardinality).to.eq(1)
      expect(cardinalityNext).to.eq(1)

      const { tickCumulative, secondsPerLiquidityCumulativeX128, blockTimestamp, initialized } =
        await oracle.getObservation(poolKey, 0)
      expect(initialized).to.be.true
      expect(blockTimestamp, 'timestamp').to.eq(3)
      expect(tickCumulative, 'cumulative tick').to.eq(13862)
      expect(secondsPerLiquidityCumulativeX128, 'seconds per liquidity').to.eq(
        '680564733841876926926749214863536422912'
      )
    })

    it('modifyPosition with time change writes an observation and updates cardinality', async () => {
      await oracle.setTime(3) // advance 2 seconds
      await oracle.increaseCardinalityNext(poolKey, 2)

      let { index, cardinality, cardinalityNext } = await oracle.getState(poolKey)
      expect(index).to.eq(0)
      expect(cardinality).to.eq(1)
      expect(cardinalityNext).to.eq(2)

      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(MAX_TICK_SPACING),
        tickUpper: getMaxTick(MAX_TICK_SPACING),
        liquidityDelta: 1000,
      })

      // cardinality is updated
      ;({ index, cardinality, cardinalityNext } = await oracle.getState(poolKey))
      expect(index).to.eq(1)
      expect(cardinality).to.eq(2)
      expect(cardinalityNext).to.eq(2)

      // index 0 is untouched
      {
        const { tickCumulative, secondsPerLiquidityCumulativeX128, blockTimestamp, initialized } =
          await oracle.getObservation(poolKey, 0)
        expect(initialized).to.be.true
        expect(blockTimestamp, 'timestamp').to.eq(1)
        expect(tickCumulative, 'cumulative tick').to.eq(0)
        expect(secondsPerLiquidityCumulativeX128, 'seconds per liquidity').to.eq(0)
      }
      // index 1 is written
      {
        const { tickCumulative, secondsPerLiquidityCumulativeX128, blockTimestamp, initialized } =
          await oracle.getObservation(poolKey, 1)
        expect(initialized).to.be.true
        expect(blockTimestamp, 'timestamp').to.eq(3)
        expect(tickCumulative, 'cumulative tick').to.eq(13862)
        expect(secondsPerLiquidityCumulativeX128, 'seconds per liquidity').to.eq(
          '680564733841876926926749214863536422912'
        )
      }
    })
  })
})
