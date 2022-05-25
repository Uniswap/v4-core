import { Wallet } from 'ethers'
import hre, { ethers, waffle } from 'hardhat'
import { LimitOrderHook, PoolManager, TestERC20 } from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import { encodeSqrtPriceX96, FeeAmount, getPoolId, getWalletForDeployingHookMask } from './shared/utilities'

const { constants } = ethers

const createFixtureLoader = waffle.createFixtureLoader

describe('LimitOrderHooks', () => {
  let wallet: Wallet, other: Wallet

  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }
  let manager: PoolManager
  let limitOrderHook: LimitOrderHook

  const fixture = async () => {
    const tokens = await tokensFixture()

    const poolManagerFactory = await ethers.getContractFactory('PoolManager')
    const limitOrderHookFactory = await ethers.getContractFactory('LimitOrderHook')

    const manager = (await poolManagerFactory.deploy()) as PoolManager

    // find a deployer that will generate a suitable hooks address
    const [hookDeployer, hookAddress] = getWalletForDeployingHookMask(
      {
        beforeInitialize: false,
        afterInitialize: true,
        beforeModifyPosition: false,
        afterModifyPosition: false,
        beforeSwap: false,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
      },
      'test onion mountain stove water behind cloud street robot salad load join'
    )

    ;[wallet] = await (ethers as any).getSigners()
    await wallet.sendTransaction({ to: hookDeployer.address, value: ethers.utils.parseEther('1') })

    // deploy the hook and make a contract instance
    await hookDeployer
      .connect(hre.ethers.provider)
      .sendTransaction(limitOrderHookFactory.getDeployTransaction(manager.address))
    const limitOrderHook = limitOrderHookFactory.attach(hookAddress) as LimitOrderHook

    const result = {
      manager,
      tokens,
      limitOrderHook,
    }

    for (const token of [tokens.token0, tokens.token1, tokens.token2]) {
      for (const spender of [limitOrderHook]) {
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
    ;({ manager, tokens, limitOrderHook } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(limitOrderHook.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#initialize', async () => {
    it('initialize a pool with limit order hook', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: limitOrderHook.address,
        },
        encodeSqrtPriceX96(1, 1)
      )

      const {
        slot0: { sqrtPriceX96 },
      } = await manager.pools(
        getPoolId({
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
          tickSpacing: 60,
          hooks: limitOrderHook.address,
        })
      )
      expect(sqrtPriceX96).to.eq(encodeSqrtPriceX96(1, 1))
    })
  })
})
