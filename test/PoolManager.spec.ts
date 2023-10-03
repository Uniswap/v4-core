import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { BigNumber, Wallet } from 'ethers'
import hre, { ethers, waffle } from 'hardhat'
import {
  EmptyTestHooks,
  PoolDonateTest,
  PoolManager,
  PoolModifyPositionTest,
  PoolSwapTest,
  PoolTakeTest,
  ProtocolFeeControllerTest,
  TestERC20,
} from '../typechain'
import { ADDRESS_ZERO, MAX_TICK_SPACING } from './shared/constants'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import { MockedContract, deployMockContract, setCode } from './shared/mockContract'
import { FeeAmount, MaxUint128, encodeSqrtPriceX96, expandTo18Decimals, getPoolId } from './shared/utilities'

const createFixtureLoader = waffle.createFixtureLoader

const { constants } = ethers

describe('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let manager: PoolManager
  let swapTest: PoolSwapTest
  let feeControllerTest: ProtocolFeeControllerTest
  let modifyPositionTest: PoolModifyPositionTest
  let donateTest: PoolDonateTest
  let takeTest: PoolTakeTest
  let hooksMock: MockedContract
  let testHooksEmpty: EmptyTestHooks
  let tokens: { currency0: TestERC20; currency1: TestERC20; token2: TestERC20 }

  const fixture = async () => {
    const poolManagerFactory = await ethers.getContractFactory('PoolManager')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const feeControllerTestFactory = await ethers.getContractFactory('ProtocolFeeControllerTest')
    const modifyPositionTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
    const donateTestFactory = await ethers.getContractFactory('PoolDonateTest')
    const takeTestFactory = await ethers.getContractFactory('PoolTakeTest')
    const hooksTestEmptyFactory = await ethers.getContractFactory('EmptyTestHooks')
    const tokens = await tokensFixture()
    const CONTROLLER_GAS_LIMIT = 50000
    const manager = (await poolManagerFactory.deploy(CONTROLLER_GAS_LIMIT)) as PoolManager

    // Deploy hooks to addresses with leading 1111 to enable all of them.
    const mockHooksAddress = '0xFF00000000000000000000000000000000000000'
    const testHooksEmptyAddress = '0xF000000000000000000000000000000000000000'

    const hookImplAddress = '0xFF00000000000000000000000000000000000001'
    setCode(hookImplAddress, 'EmptyTestHooks')
    hooksMock = await deployMockContract(hooksTestEmptyFactory.interface, mockHooksAddress, hookImplAddress)

    await hre.network.provider.send('hardhat_setCode', [
      testHooksEmptyAddress,
      (await hre.artifacts.readArtifact('EmptyTestHooks')).deployedBytecode,
    ])

    const testHooksEmpty: EmptyTestHooks = hooksTestEmptyFactory.attach(testHooksEmptyAddress) as EmptyTestHooks

    const result = {
      manager,
      swapTest: (await swapTestFactory.deploy(manager.address)) as PoolSwapTest,
      feeControllerTest: (await feeControllerTestFactory.deploy()) as ProtocolFeeControllerTest,
      modifyPositionTest: (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest,
      donateTest: (await donateTestFactory.deploy(manager.address)) as PoolDonateTest,
      takeTest: (await takeTestFactory.deploy(manager.address)) as PoolTakeTest,
      tokens,
      hooksMock,
      testHooksEmpty,
    }

    for (const token of [tokens.currency0, tokens.currency1, tokens.token2]) {
      for (const spender of [result.swapTest, result.modifyPositionTest, result.donateTest, result.takeTest]) {
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
    ;({
      manager,
      tokens,
      modifyPositionTest,
      swapTest,
      feeControllerTest,
      donateTest,
      takeTest,
      hooksMock,
      testHooksEmpty,
    } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(manager.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#take', () => {
    it('fails if no liquidity', async () => {
      await tokens.currency0.connect(wallet).transfer(ADDRESS_ZERO, constants.MaxUint256.div(2))
      await expect(
        takeTest.connect(wallet).take(
          {
            currency0: tokens.currency0.address,
            currency1: tokens.currency1.address,
            fee: 100,
            hooks: ADDRESS_ZERO,
            tickSpacing: 10,
          },
          100,
          0
        )
      ).to.be.reverted
    })

    it('fails for invalid tokens that dont return true on transfer', async () => {
      const tokenFactory = await ethers.getContractFactory('TestInvalidERC20')
      const invalidToken = (await tokenFactory.deploy(BigNumber.from(2).pow(255))) as TestERC20
      const currency0Invalid = invalidToken.address.toLowerCase() < tokens.currency0.address.toLowerCase()
      const key = {
        currency0: currency0Invalid ? invalidToken.address : tokens.currency0.address,
        currency1: currency0Invalid ? tokens.currency0.address : invalidToken.address,
        fee: 100,
        hooks: ADDRESS_ZERO,
        tickSpacing: 10,
      }
      await invalidToken.approve(modifyPositionTest.address, constants.MaxUint256)
      await manager.initialize(key, encodeSqrtPriceX96(1, 1), '0x00')
      await modifyPositionTest.modifyPosition(
        key,
        {
          tickLower: -60,
          tickUpper: 60,
          liquidityDelta: 100,
        },
        '0x00'
      )

      await tokens.currency0.connect(wallet).approve(takeTest.address, MaxUint128)
      await invalidToken.connect(wallet).approve(takeTest.address, MaxUint128)

      await expect(takeTest.connect(wallet).take(key, currency0Invalid ? 1 : 0, currency0Invalid ? 0 : 1)).to.be
        .reverted
      await expect(takeTest.connect(wallet).take(key, currency0Invalid ? 0 : 1, currency0Invalid ? 1 : 0)).to.not.be
        .reverted
    })

    it('succeeds if has liquidity', async () => {
      const key = {
        currency0: tokens.currency0.address,
        currency1: tokens.currency1.address,
        fee: 100,
        hooks: ADDRESS_ZERO,
        tickSpacing: 10,
      }
      await manager.initialize(key, encodeSqrtPriceX96(1, 1), '0x00')
      await modifyPositionTest.modifyPosition(
        key,
        {
          tickLower: -60,
          tickUpper: 60,
          liquidityDelta: 100,
        },
        '0x00'
      )

      await tokens.currency0.connect(wallet).approve(takeTest.address, MaxUint128)

      await expect(takeTest.connect(wallet).take(key, 1, 0)).to.be.not.be.reverted
      await expect(takeTest.connect(wallet).take(key, 0, 1)).to.be.not.be.reverted
    })

    it('succeeds with native tokens if has liquidity', async () => {
      const key = {
        currency0: ADDRESS_ZERO,
        currency1: tokens.currency1.address,
        fee: 100,
        hooks: ADDRESS_ZERO,
        tickSpacing: 10,
      }
      await manager.initialize(key, encodeSqrtPriceX96(1, 1), '0x00')
      await modifyPositionTest.modifyPosition(
        key,
        {
          tickLower: -60,
          tickUpper: 60,
          liquidityDelta: 100,
        },
        '0x00',
        { value: 100 }
      )

      await tokens.currency0.connect(wallet).approve(takeTest.address, MaxUint128)

      await expect(takeTest.connect(wallet).take(key, 1, 0, { value: 1 })).to.be.not.be.reverted
      await expect(takeTest.connect(wallet).take(key, 0, 1)).to.be.not.be.reverted
    })
  })

  describe('#setPoolProtocolFee', async () => {
    it('updates the protocol fee for an initialised pool', async () => {
      expect(await manager.protocolFeeController()).to.be.eq(ADDRESS_ZERO)

      const poolKey = {
        currency0: tokens.currency0.address,
        currency1: tokens.currency1.address,
        fee: FeeAmount.MEDIUM,
        tickSpacing: 60,
        hooks: ADDRESS_ZERO,
      }
      const poolID = getPoolId(poolKey)

      await manager.initialize(poolKey, encodeSqrtPriceX96(10, 1), '0x00')

      var protocolFees: number
      ;({
        slot0: { protocolFees },
      } = await manager.pools(getPoolId(poolKey)))
      expect(protocolFees).to.eq(0)

      await manager.setProtocolFeeController(feeControllerTest.address)
      expect(await manager.protocolFeeController()).to.be.eq(feeControllerTest.address)
      const poolProtocolSwapFee = 4
      await feeControllerTest.setSwapFeeForPool(poolID, poolProtocolSwapFee)

      await expect(manager.setProtocolFees(poolKey))
        .to.emit(manager, 'ProtocolFeeUpdated')
        .withArgs(poolID, BigNumber.from(poolProtocolSwapFee).shl(12))
      ;({
        slot0: { protocolFees },
      } = await manager.pools(poolID))
      expect(protocolFees).to.eq(BigNumber.from(poolProtocolSwapFee).shl(12))
    })
  })

  describe('#collectProtocolFees', async () => {
    describe('ERC20 tokens', async () => {
      beforeEach('set the fee controller, initialize a pool with protocol fee', async () => {
        const poolKey = {
          currency0: tokens.currency0.address,
          currency1: tokens.currency1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        }
        // set the controller, and set the pool's protocol fee
        await manager.setProtocolFeeController(feeControllerTest.address)
        expect(await manager.protocolFeeController()).to.be.eq(feeControllerTest.address)
        const poolProtocolFee = 260 // 0x 0001 00 00 0100
        const poolID = getPoolId(poolKey)
        await feeControllerTest.setSwapFeeForPool(poolID, poolProtocolFee)

        // initialize the pool with the fee
        await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1), '0x00')
        const {
          slot0: { protocolFees },
        } = await manager.pools(getPoolId(poolKey))
        expect(protocolFees).to.eq(BigNumber.from(poolProtocolFee).shl(12))

        // add liquidity around the initial price
        await modifyPositionTest.modifyPosition(
          poolKey,
          {
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: expandTo18Decimals(10),
          },
          '0x00'
        )
      })

      it('allows the owner to collect accumulated fees', async () => {
        await swapTest.swap(
          {
            currency0: tokens.currency0.address,
            currency1: tokens.currency1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 10000,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          },
          '0x00'
        )

        const expectedFees = 7
        expect(await manager.protocolFeesAccrued(tokens.currency0.address)).to.be.eq(BigNumber.from(expectedFees))
        expect(await manager.protocolFeesAccrued(tokens.currency1.address)).to.be.eq(BigNumber.from(0))

        // allows the owner to collect the fees
        const recipientBalanceBefore = await tokens.currency0.balanceOf(other.address)
        const managerBalanceBefore = await tokens.currency0.balanceOf(manager.address)

        // get the returned value, then actually execute
        const amount = await manager.callStatic.collectProtocolFees(other.address, tokens.currency0.address, 7)
        await manager.collectProtocolFees(other.address, tokens.currency0.address, expectedFees)

        const recipientBalanceAfter = await tokens.currency0.balanceOf(other.address)
        const managerBalanceAfter = await tokens.currency0.balanceOf(manager.address)

        expect(amount).to.be.eq(expectedFees)
        expect(recipientBalanceAfter).to.be.eq(recipientBalanceBefore.add(expectedFees))
        expect(managerBalanceAfter).to.be.eq(managerBalanceBefore.sub(expectedFees))

        expect(await manager.protocolFeesAccrued(tokens.currency0.address)).to.be.eq(BigNumber.from(0))
      })

      it('returns all fees if 0 is provided', async () => {
        await swapTest.swap(
          {
            currency0: tokens.currency0.address,
            currency1: tokens.currency1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 10000,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          },
          '0x00'
        )

        const expectedFees = 7
        expect(await manager.protocolFeesAccrued(tokens.currency0.address)).to.be.eq(BigNumber.from(expectedFees))
        expect(await manager.protocolFeesAccrued(tokens.currency1.address)).to.be.eq(BigNumber.from(0))

        // allows the owner to collect the fees
        const recipientBalanceBefore = await tokens.currency0.balanceOf(other.address)
        const managerBalanceBefore = await tokens.currency0.balanceOf(manager.address)

        // get the returned value, then actually execute
        const amount = await manager.callStatic.collectProtocolFees(other.address, tokens.currency0.address, 0)
        await manager.collectProtocolFees(other.address, tokens.currency0.address, 0)

        const recipientBalanceAfter = await tokens.currency0.balanceOf(other.address)
        const managerBalanceAfter = await tokens.currency0.balanceOf(manager.address)

        expect(amount).to.be.eq(expectedFees)
        expect(recipientBalanceAfter).to.be.eq(recipientBalanceBefore.add(expectedFees))
        expect(managerBalanceAfter).to.be.eq(managerBalanceBefore.sub(expectedFees))

        expect(await manager.protocolFeesAccrued(tokens.currency0.address)).to.be.eq(BigNumber.from(0))
      })
    })

    describe('native tokens', async () => {
      beforeEach('set the fee controller, initialize a pool with protocol fee', async () => {
        const poolKey = {
          currency0: ADDRESS_ZERO,
          currency1: tokens.currency1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: ADDRESS_ZERO,
        }
        // set the controller, and set the pool's protocol fee
        await manager.setProtocolFeeController(feeControllerTest.address)
        expect(await manager.protocolFeeController()).to.be.eq(feeControllerTest.address)
        const poolProtocolFee = 260 // 0x 0001 00 00 0100
        const poolID = getPoolId(poolKey)
        await feeControllerTest.setSwapFeeForPool(poolID, poolProtocolFee)

        // initialize the pool with the fee
        await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1), '0x00')
        const {
          slot0: { protocolFees },
        } = await manager.pools(getPoolId(poolKey))
        expect(protocolFees).to.eq(BigNumber.from(poolProtocolFee).shl(12))

        // add liquidity around the initial price
        await modifyPositionTest.modifyPosition(
          poolKey,
          {
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: expandTo18Decimals(10),
          },
          '0x00',
          {
            value: expandTo18Decimals(10),
          }
        )
      })

      it('allows the owner to collect accumulated fees', async () => {
        await swapTest.swap(
          {
            currency0: ADDRESS_ZERO,
            currency1: tokens.currency1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 10000,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          },
          '0x00',
          {
            value: 10000,
          }
        )

        const expectedFees = 7
        expect(await manager.protocolFeesAccrued(ADDRESS_ZERO)).to.be.eq(BigNumber.from(expectedFees))
        expect(await manager.protocolFeesAccrued(tokens.currency1.address)).to.be.eq(BigNumber.from(0))

        // allows the owner to collect the fees
        const recipientBalanceBefore = await other.getBalance()
        const managerBalanceBefore = await waffle.provider.getBalance(manager.address)

        // get the returned value, then actually execute
        const amount = await manager.callStatic.collectProtocolFees(other.address, ADDRESS_ZERO, 7)
        await manager.collectProtocolFees(other.address, ADDRESS_ZERO, expectedFees)

        const recipientBalanceAfter = await other.getBalance()
        const managerBalanceAfter = await waffle.provider.getBalance(manager.address)

        expect(amount).to.be.eq(expectedFees)
        expect(recipientBalanceAfter).to.be.eq(recipientBalanceBefore.add(expectedFees))
        expect(managerBalanceAfter).to.be.eq(managerBalanceBefore.sub(expectedFees))

        expect(await manager.protocolFeesAccrued(ADDRESS_ZERO)).to.be.eq(BigNumber.from(0))
      })

      it('returns all fees if 0 is provided', async () => {
        await swapTest.swap(
          {
            currency0: ADDRESS_ZERO,
            currency1: tokens.currency1.address,
            fee: FeeAmount.MEDIUM,
            tickSpacing: 60,
            hooks: ADDRESS_ZERO,
          },
          {
            amountSpecified: 10000,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          },
          '0x00',
          {
            value: 10000,
          }
        )

        const expectedFees = 7
        expect(await manager.protocolFeesAccrued(ADDRESS_ZERO)).to.be.eq(BigNumber.from(expectedFees))
        expect(await manager.protocolFeesAccrued(tokens.currency1.address)).to.be.eq(BigNumber.from(0))

        // allows the owner to collect the fees
        const recipientBalanceBefore = await other.getBalance()
        const managerBalanceBefore = await waffle.provider.getBalance(manager.address)

        // get the returned value, then actually execute
        const amount = await manager.callStatic.collectProtocolFees(other.address, ADDRESS_ZERO, 0)
        await manager.collectProtocolFees(other.address, ADDRESS_ZERO, 0)

        const recipientBalanceAfter = await other.getBalance()
        const managerBalanceAfter = await waffle.provider.getBalance(manager.address)

        expect(amount).to.be.eq(expectedFees)
        expect(recipientBalanceAfter).to.be.eq(recipientBalanceBefore.add(expectedFees))
        expect(managerBalanceAfter).to.be.eq(managerBalanceBefore.sub(expectedFees))

        expect(await manager.protocolFeesAccrued(ADDRESS_ZERO)).to.be.eq(BigNumber.from(0))
      })
    })
  })
})
