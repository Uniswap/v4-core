import { Contract, ContractFactory, Wallet } from 'ethers'
import hre from 'hardhat'
import { ethers, waffle } from 'hardhat'
import {
  PoolManager,
  TestERC20,
  PoolManagerTest,
  PoolSwapTest,
  PoolModifyPositionTest,
  EmptyTestHooks,
} from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, expandTo18Decimals, FeeAmount, getPoolId } from './shared/utilities'
import { FormatTypes, Interface } from 'ethers/lib/utils'
import { deployMockContract, MockedContract } from './shared/mockContract'

const createFixtureLoader = waffle.createFixtureLoader

const { constants } = ethers

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000'

describe('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let manager: PoolManager
  let lockTest: PoolManagerTest
  let swapTest: PoolSwapTest
  let modifyPositionTest: PoolModifyPositionTest
  let hooksMock: MockedContract
  let testHooksEmpty: EmptyTestHooks
  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }

  const fixture = async () => {
    const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
    const managerTestFactory = await ethers.getContractFactory('PoolManagerTest')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const modifyPositionTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
    const hooksTestEmptyFactory = await ethers.getContractFactory('EmptyTestHooks')
    const tokens = await tokensFixture()
    const manager = (await singletonPoolFactory.deploy()) as PoolManager

    // Deploy hooks to addresses with leading 1111 to enable all of them.
    const mockHooksAddress = '0xFF00000000000000000000000000000000000000'
    const testHooksEmptyAddress = '0xF000000000000000000000000000000000000000'

    hooksMock = await deployMockContract(hooksTestEmptyFactory.interface, mockHooksAddress)

    await hre.network.provider.send('hardhat_setCode', [
      testHooksEmptyAddress,
      (await hre.artifacts.readArtifact('EmptyTestHooks')).deployedBytecode,
    ])

    const testHooksEmpty: EmptyTestHooks = hooksTestEmptyFactory.attach(testHooksEmptyAddress) as EmptyTestHooks

    const result = {
      manager,
      lockTest: (await managerTestFactory.deploy()) as PoolManagerTest,
      swapTest: (await swapTestFactory.deploy(manager.address)) as PoolSwapTest,
      modifyPositionTest: (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest,
      tokens,
      hooksMock,
      testHooksEmpty,
    }

    for (const token of [tokens.token0, tokens.token1, tokens.token2]) {
      for (const spender of [result.swapTest, result.modifyPositionTest]) {
        await token.connect(wallet).approve(spender.address, constants.MaxUint256)
      }
    }

    return result
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader([wallet, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ manager, tokens, lockTest, modifyPositionTest, swapTest, hooksMock, testHooksEmpty } = await loadFixture(
      fixture
    ))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(manager.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#lock', () => {
    it('no-op lock is ok', async () => {
      await lockTest.lock(manager.address)
    })

    it('gas overhead of no-op lock', async () => {
      await snapshotGasCost(lockTest.lock(manager.address))
    })
  })

  describe('#initialize', async () => {
    it('initializes a pool', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(10, 1)
      )

      const {
        slot0: { sqrtPriceX96 },
      } = await manager.pools(
        getPoolId({
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        })
      )
      expect(sqrtPriceX96).to.eq(encodeSqrtPriceX96(10, 1))
    })

    it('initializes a pool with hooks', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        encodeSqrtPriceX96(10, 1)
      )

      const {
        slot0: { sqrtPriceX96 },
      } = await manager.pools(
        getPoolId({
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        })
      )
      expect(sqrtPriceX96).to.eq(encodeSqrtPriceX96(10, 1))
    })

    it('gas cost', async () => {
      await snapshotGasCost(
        manager.initialize(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          encodeSqrtPriceX96(10, 1)
        )
      )
    })
  })

  describe('#mint', async () => {
    it('reverts if pool not initialized', async () => {
      await expect(
        modifyPositionTest.modifyPosition(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            tickLower: 0,
            tickUpper: 60,
            liquidityDelta: 100,
          }
        )
      ).to.be.revertedWith('I')
    })

    it('succeeds if pool is initialized', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await modifyPositionTest.modifyPosition(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        {
          tickLower: 0,
          tickUpper: 60,
          liquidityDelta: 100,
        }
      )
    })

    it('succeeds if pool is initialized and hook is provided', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await modifyPositionTest.modifyPosition(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        {
          tickLower: 0,
          tickUpper: 60,
          liquidityDelta: 100,
        }
      )

      const argsBeforeModify = [
        modifyPositionTest.address,
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        {
          tickLower: 0,
          tickUpper: 60,
          liquidityDelta: 100,
        },
      ]
      const argsAfterModify = [...argsBeforeModify, { amount0: 1, amount1: 0 }]

      expect(await hooksMock.calledWith('beforeModifyPosition', argsBeforeModify)).to.be.true
      expect(await hooksMock.calledOnce('beforeModifyPosition')).to.be.true
      expect(await hooksMock.calledWith('afterModifyPosition', argsAfterModify)).to.be.true
      expect(await hooksMock.called('afterModifyPosition')).to.be.true

      expect(await hooksMock.called('beforeSwap')).to.be.false
      expect(await hooksMock.called('afterSwap')).to.be.false
    })

    it('gas cost', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await snapshotGasCost(
        modifyPositionTest.modifyPosition(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            tickLower: 0,
            tickUpper: 60,
            liquidityDelta: 100,
          }
        )
      )
    })

    it('gas cost with hooks', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: testHooksEmpty.address,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await snapshotGasCost(
        modifyPositionTest.modifyPosition(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: testHooksEmpty.address,
          },
          {
            tickLower: 0,
            tickUpper: 60,
            liquidityDelta: 100,
          }
        )
      )
    })
  })

  describe('#swap', () => {
    it('fails if pool is not initialized', async () => {
      await expect(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          }
        )
      ).to.be.revertedWith('I')
    })
    it('succeeds if pool is initialized', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )
    })
    it('succeeds if pool is initialized and hook is provided', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      const argsBeforeSwap = [
        swapTest.address,
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: hooksMock.address,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        },
      ]

      const argsAfterSwap = [...argsBeforeSwap, { amount0: 0, amount1: 0 }]

      expect(await hooksMock.called('beforeModifyPosition')).to.be.false
      expect(await hooksMock.called('afterModifyPosition')).to.be.false
      expect(await hooksMock.calledOnce('beforeSwap')).to.be.true
      expect(await hooksMock.calledOnce('afterSwap')).to.be.true
      expect(await hooksMock.calledWith('beforeSwap', argsBeforeSwap)).to.be.true
      expect(await hooksMock.calledWith('afterSwap', argsAfterSwap)).to.be.true
    })
    it('gas cost', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      await snapshotGasCost(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 4),
            zeroForOne: true,
          }
        )
      )
    })
    it('gas cost with hooks', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: testHooksEmpty.address,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: testHooksEmpty.address,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      await snapshotGasCost(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: testHooksEmpty.address,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 4),
            zeroForOne: true,
          }
        )
      )
    })
    it('gas cost for swap against liquidity', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await modifyPositionTest.modifyPosition(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        {
          tickLower: -120,
          tickUpper: 120,
          liquidityDelta: expandTo18Decimals(1),
        }
      )

      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      await snapshotGasCost(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 4),
            zeroForOne: true,
          }
        )
      )
    })
  })
})
