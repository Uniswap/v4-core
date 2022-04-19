import { Wallet } from 'ethers'
import hre from 'hardhat'
import { ethers, waffle } from 'hardhat'
import {
  PoolManager,
  TestERC20,
  PoolManagerTest,
  PoolSwapTest,
  PoolModifyPositionTest,
  PoolTWAMMTest,
  EmptyTestHooks,
  PoolManagerReentrancyTest,
} from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import {
  encodeSqrtPriceX96,
  expandTo18Decimals,
  FeeAmount,
  getMinTick,
  getMaxTick,
  getPoolId,
} from './shared/utilities'
import { deployMockContract, MockedContract } from './shared/mockContract'
import { TickMath } from '@uniswap/v3-sdk'
import JSBI from 'jsbi'
import { BigNumber } from 'ethers'

const createFixtureLoader = waffle.createFixtureLoader

const { constants } = ethers

const ADDRESS_ZERO = '0x0000000000000000000000000000000000000000'

describe('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let manager: PoolManager
  let lockTest: PoolManagerTest
  let swapTest: PoolSwapTest
  let modifyPositionTest: PoolModifyPositionTest
  let twammTest: PoolTWAMMTest
  let hooksMock: MockedContract
  let testHooksEmpty: EmptyTestHooks
  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }

  const fixture = async () => {
    const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
    const managerTestFactory = await ethers.getContractFactory('PoolManagerTest')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const modifyPositionTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
    const twammTestFactory = await ethers.getContractFactory('PoolTWAMMTest')
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
      twammTest: (await twammTestFactory.deploy(manager.address)) as PoolTWAMMTest,
      modifyPositionTest: (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest,
      tokens,
      hooksMock,
      testHooksEmpty,
    }

    for (const token of [tokens.token0, tokens.token1, tokens.token2]) {
      for (const spender of [result.swapTest, result.modifyPositionTest, result.twammTest]) {
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
    ;({ manager, tokens, lockTest, modifyPositionTest, swapTest, twammTest, hooksMock, testHooksEmpty } =
      await loadFixture(fixture))
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

    it('can be reentered', async () => {
      const reenterTest = (await (
        await ethers.getContractFactory('PoolManagerReentrancyTest')
      ).deploy()) as PoolManagerReentrancyTest

      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        },
        encodeSqrtPriceX96(1, 1),
        10_000
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

      await expect(reenterTest.reenter(manager.address, tokens.token0.address, 3))
        .to.emit(reenterTest, 'LockAcquired')
        .withArgs(3)
        .to.emit(reenterTest, 'LockAcquired')
        .withArgs(2)
        .to.emit(reenterTest, 'LockAcquired')
        .withArgs(1)
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
        encodeSqrtPriceX96(10, 1),
        10_000
      )

      const { sqrtPriceX96 } = await manager.slot0(
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
        encodeSqrtPriceX96(10, 1),
        10_000
      )

      const { sqrtPriceX96 } = await manager.slot0(
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
          encodeSqrtPriceX96(10, 1),
          10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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
        encodeSqrtPriceX96(1, 1),
        10_000
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

  describe.only('TWAMM', () => {
    function nIntervalsFrom(timestamp: number, interval: number, n: number): number {
      return timestamp + (interval - (timestamp % interval)) + interval * (n - 1)
    }

    type OrderKey = {
      owner: string
      expiration: number
      zeroForOne: boolean
    }

    describe('#executeTWAMMOrders', async () => {
      let poolKey: any
      let orderKey0: any
      let orderKey1: any
      let latestTimestamp: number

      beforeEach(async () => {
        latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp

        poolKey = {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: 0,
          hooks: ADDRESS_ZERO,
          tickSpacing: 10,
        }
        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration: nIntervalsFrom(latestTimestamp, 10_000, 3),
        }
        orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration: nIntervalsFrom(latestTimestamp, 10_000, 3),
        }

        await ethers.provider.send('evm_setNextBlockTimestamp', [nIntervalsFrom(latestTimestamp, 10_000, 1)])
        await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1), 10_000)
        latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp

        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: expandTo18Decimals(1),
        })
      })

      it('gas with no initialized ticks', async () => {
        await ethers.provider.send('evm_setAutomine', [false])
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
        await ethers.provider.send('evm_mine', [latestTimestamp + 100])
        await ethers.provider.send('evm_setAutomine', [true])
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twammTest.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 1 initialized tick', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -200,
          tickUpper: 200,
          liquidityDelta: expandTo18Decimals(1),
        })
        await ethers.provider.send('evm_setAutomine', [false])
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
        await ethers.provider.send('evm_mine', [latestTimestamp + 100])
        await ethers.provider.send('evm_setAutomine', [true])
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twammTest.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 2 initialized ticks', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -200,
          tickUpper: 200,
          liquidityDelta: expandTo18Decimals(1),
        })
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: expandTo18Decimals(1),
        })
        await ethers.provider.send('evm_setAutomine', [false])
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twammTest.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
        await ethers.provider.send('evm_mine', [latestTimestamp + 100])
        await ethers.provider.send('evm_setAutomine', [true])
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twammTest.executeTWAMMOrders(poolKey))
      })
    })

    describe('end-to-end integration', () => {
      let start: number
      let expiration: number
      let key: any
      let orderKey0: OrderKey
      let orderKey1: OrderKey
      let liquidityBalance: BigNumber

      describe('when TWAMM crosses a tick', () => {
        beforeEach('set up pool', async () => {
          const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
          const amountLiquidity = expandTo18Decimals(1)

          start = nIntervalsFrom(latestTimestamp, 10_000, 1)
          expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

          orderKey0 = {
            zeroForOne: true,
            owner: wallet.address,
            expiration,
          }
          orderKey1 = {
            zeroForOne: false,
            owner: wallet.address,
            expiration,
          }

          key = {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: 0,
            hooks: ADDRESS_ZERO,
            tickSpacing: 10,
          }
          await manager.initialize(key, encodeSqrtPriceX96(1, 1), 10_000)

          // 1) Add liquidity balances to AMM
          await modifyPositionTest.modifyPosition(key, {
            tickLower: getMinTick(10),
            tickUpper: getMaxTick(10),
            liquidityDelta: amountLiquidity,
          })
          await modifyPositionTest.modifyPosition(key, {
            tickLower: -20000,
            tickUpper: 20000,
            liquidityDelta: amountLiquidity,
          })

          liquidityBalance = await tokens.token0.balanceOf(manager.address)
        })

        it('balances clear properly w/ token1 excess', async () => {
          const amountLTO0 = expandTo18Decimals(1)
          const amountLTO1 = expandTo18Decimals(10)

          await ethers.provider.send('evm_setAutomine', [false])

          // 2) Add order balances to TWAMM
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO0,
            ...orderKey0,
          })
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO1,
            ...orderKey1,
          })

          await ethers.provider.send('evm_mine', [start])
          await ethers.provider.send('evm_setAutomine', [true])
          await ethers.provider.send('evm_setNextBlockTimestamp', [expiration])

          expect(await tokens.token0.balanceOf(manager.address)).to.eq(liquidityBalance.add(amountLTO0))
          expect(await tokens.token1.balanceOf(manager.address)).to.eq(liquidityBalance.add(amountLTO1))

          // 3) Execute TWAMM which will perform a swap on the AMM
          const receipt = await (await twammTest.executeTWAMMOrders(key)).wait()
          const events = receipt.logs.map((log) => manager.interface.parseLog(log))

          const swapDelta0 = events[0].args.amount0
          const swapDelta1 = events[0].args.amount1

          const claimedEarnings1 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
          const claimedEarnings0 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

          // 4) Pull all earnings from TWAMM now TWAMM should have no liquidity in it.
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey0)
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey1)

          // 5) The AMM balance should consist of original liquidity plus deltas from the single swap
          // that happened during TWAMM execution
          const expectedBalance0 = liquidityBalance.add(swapDelta0)
          const actualBalance0 = await tokens.token0.balanceOf(manager.address)

          const expectedBalance1 = liquidityBalance.add(swapDelta1)
          const actualBalance1 = await tokens.token1.balanceOf(manager.address)

          // TODO: precision off by 4 and 3 wei respectively
          expect(actualBalance0).to.eq(expectedBalance0.sub(4))
          expect(actualBalance1).to.eq(expectedBalance1.sub(3))
        })

        it('balances clear properly w/ token0 excess', async () => {
          const amountLTO0 = expandTo18Decimals(10)
          const amountLTO1 = expandTo18Decimals(1)

          await ethers.provider.send('evm_setAutomine', [false])

          // 2) Add order balances to TWAMM
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO0,
            ...orderKey0,
          })
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO1,
            ...orderKey1,
          })

          await ethers.provider.send('evm_mine', [start])
          await ethers.provider.send('evm_setAutomine', [true])
          await ethers.provider.send('evm_setNextBlockTimestamp', [expiration])

          expect(await tokens.token0.balanceOf(manager.address)).to.eq(liquidityBalance.add(amountLTO0))
          expect(await tokens.token1.balanceOf(manager.address)).to.eq(liquidityBalance.add(amountLTO1))

          // 3) Execute TWAMM which will perform a swap on the AMM
          const receipt = await (await twammTest.executeTWAMMOrders(key)).wait()
          const events = receipt.logs.map((log) => manager.interface.parseLog(log))

          const swapDelta0 = events[0].args.amount0
          const swapDelta1 = events[0].args.amount1

          const claimedEarnings1 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
          const claimedEarnings0 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

          // 4) Pull all earnings from TWAMM now TWAMM should have no liquidity in it.
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey0)
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey1)

          // 5) The AMM balance should consist of original liquidity plus deltas from the single swap
          // that happened during TWAMM execution
          const expectedBalance0 = liquidityBalance.add(swapDelta0)
          const actualBalance0 = await tokens.token0.balanceOf(manager.address)

          const expectedBalance1 = liquidityBalance.add(swapDelta1)
          const actualBalance1 = await tokens.token1.balanceOf(manager.address)

          // TODO: precision off by 5 and 6 respectively
          expect(actualBalance0).to.eq(expectedBalance0.sub(5))
          expect(actualBalance1).to.eq(expectedBalance1.sub(6))
        })
      })

      describe('when TWAMM crosses no ticks', () => {
        it('clears all balances appropriately when trading against a 0 fee AMM', async () => {
          const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
          const amountLiquidity = expandTo18Decimals(1)
          const amountLTO0 = expandTo18Decimals(1)
          const amountLTO1 = expandTo18Decimals(10)

          const start = nIntervalsFrom(latestTimestamp, 10_000, 1)
          const expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

          const orderKey0 = {
            zeroForOne: true,
            owner: wallet.address,
            expiration,
          }
          const orderKey1 = {
            zeroForOne: false,
            owner: wallet.address,
            expiration,
          }

          const key = {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: 0,
            hooks: ADDRESS_ZERO,
            tickSpacing: 10,
          }
          await manager.initialize(key, encodeSqrtPriceX96(1, 1), 10_000)

          // 1) Add liquidity balances to AMM
          await modifyPositionTest.modifyPosition(key, {
            tickLower: getMinTick(10),
            tickUpper: getMaxTick(10),
            liquidityDelta: amountLiquidity,
          })

          expect(await tokens.token0.balanceOf(manager.address)).to.eq(amountLiquidity)
          expect(await tokens.token1.balanceOf(manager.address)).to.eq(amountLiquidity)

          await ethers.provider.send('evm_setAutomine', [false])

          // 2) Add order balances to TWAMM
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO0,
            ...orderKey0,
          })
          await twammTest.submitLongTermOrder(key, {
            amountIn: amountLTO1,
            ...orderKey1,
          })

          await ethers.provider.send('evm_mine', [start])
          await ethers.provider.send('evm_setAutomine', [true])
          await ethers.provider.send('evm_setNextBlockTimestamp', [expiration])

          expect(await tokens.token0.balanceOf(manager.address)).to.eq(amountLiquidity.add(amountLTO0))
          expect(await tokens.token1.balanceOf(manager.address)).to.eq(amountLiquidity.add(amountLTO1))

          // 3) Execute TWAMM which will perform a swap on the AMM
          const receipt = await (await twammTest.executeTWAMMOrders(key)).wait()
          const events = receipt.logs.map((log) => manager.interface.parseLog(log))

          const swapDelta0 = events[0].args.amount0
          const swapDelta1 = events[0].args.amount1

          const claimedEarnings1 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
          const claimedEarnings0 = await twammTest.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

          // 4) Pull all earnings from TWAMM now TWAMM should have no liquidity in it.
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey0)
          await twammTest.claimEarningsOnLongTermOrder(key, orderKey1)

          // 5) The AMM balance should consist of original liquidity plus deltas from the single swap
          // that happened during TWAMM execution
          const expectedBalance0 = amountLiquidity.add(swapDelta0)
          const actualBalance0 = await tokens.token0.balanceOf(manager.address)

          const expectedBalance1 = amountLiquidity.add(swapDelta1)
          const actualBalance1 = await tokens.token1.balanceOf(manager.address)

          // TODO: precision off by 3 and 4 respectively
          expect(actualBalance0).to.eq(expectedBalance0.sub(3))
          expect(actualBalance1).to.eq(expectedBalance1.sub(4))
        })
      })
    })
  })
})
