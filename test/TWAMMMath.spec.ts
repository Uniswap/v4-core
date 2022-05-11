import { TWAMMTest } from '../typechain/TWAMMTest'
import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, MaxUint128 } from './shared/utilities'

function toWei(n: string): BigNumber {
  return ethers.utils.parseEther(n)
}

function divX96(n: BigNumber): string {
  return (parseInt(n.toString()) / 2 ** 96).toFixed(7).toString()
}

describe('TWAMMMath', () => {
  let twamm: TWAMMTest
  let wallet: Wallet, other: Wallet
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy()) as TWAMMTest
  }

  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  beforeEach(async () => {
    twamm = await loadFixture(twammFixture)
  })

  describe('#calculateExecutionUpdates outputs the correct results when', () => {
    let secondsElapsedX96: BigNumberish
    let sqrtPriceX96: BigNumberish
    let liquidity: BigNumberish
    let fee: BigNumberish
    let tickSpacing: BigNumberish
    let sellRateCurrent0: BigNumberish
    let sellRateCurrent1: BigNumberish

    beforeEach(async () => {
      secondsElapsedX96 = BigNumber.from(3600).mul(BigNumber.from(2).pow(96))
      sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      liquidity = '1000000000000000000000000'
      fee = '3000'
      tickSpacing = '60'
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('1')
    })

    // Outputting results without FixedPointX96 format to compare more easily with desmos
    // https://www.desmos.com/calculator/aszdsyhxjk
    const TEST_CASES = [
      {
        title: 'price is one, sell rates are equal',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '1.0000000',
          amountOut0: '3600.0000000',
          amountOut1: '3600.0000000',
        },
      },
      {
        title: 'price is one, sell rate is 5',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('5'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '0.9858549',
          amountOut0: '3549.0165948',
          amountOut1: '3651.9628500',
        },
      },
      {
        title: 'price is one, sell rate is 10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('10'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '0.9687272',
          amountOut0: '3487.2827245',
          amountOut1: '3717.6111869',
        },
      },
      {
        title: 'price is one, sell rate is 1/5',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('5'),
        },
        outputsDivX96: {
          price: '1.0143480',
          amountOut0: '3651.9628500',
          amountOut1: '3549.0165948',
        },
      },
      {
        title: 'price is one, sell rate is 1/10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('10'),
        },
        outputsDivX96: {
          price: '1.0322824',
          amountOut0: '3717.6111869',
          amountOut1: '3487.2827245',
        },
      },
      {
        title: 'price is high, sell rate is 1/10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(123456, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('10'),
        },
        outputsDivX96: {
          price: '155.1531845',
          amountOut0: '196245875.5487389',
          amountOut1: '0.0815851',
        },
      },
      {
        title: 'sell rate is extremely large',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('100000000'),
          sellRate1: toWei('5'),
        },
        outputsDivX96: {
          price: '0.0002236',
          amountOut0: '0.0101778',
          amountOut1: '71105772809.0000916',
        },
      },
      {
        title: 'when sell rate is extremely small',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('5'),
          sellRate1: toWei('100000000'),
        },
        outputsDivX96: {
          price: '4472.1359550',
          amountOut0: '71105772809.0000916',
          amountOut1: '0.0101778',
        },
      },
      // TODO: not working - amounts out are incorrect from desmos, not enough precision??
      // {
      //   title: 'sell rates are extremely low compared to pool liquidity',
      //   inputs: {
      //     sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      //     sellRate0: '10000',
      //     sellRate1: '500',
      //   },
      //   outputsDivX96: {
      //     price: '1.0000000',
      //     amountOut0: '180.0000000',
      //     amountOut1: '72000.0000000',
      //   },
      // },
      // TODO: not working - desmos also is turning up invalid numbers (like negative earnings accumulators)
      // {
      //   title: 'sell rate of 1 wei in a pool with liquidity amounts that accommodates 18 token decimals',
      //   inputs: {
      //     sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      //     sellRate0: '5',
      //     sellRate1: '10000',
      //   },
      //   outputsDivX96: {
      //     price: '1.0000000',
      //     amountOut0: '184835683.94',
      //     amountOut1: '-88816.04197',
      //   },
      // },
    ]

    for (let testcase of TEST_CASES) {
      it(testcase.title, async () => {
        const results = await twamm.callStatic.calculateExecutionUpdates(
          {
            secondsElapsedX96,
            sqrtPriceX96: testcase.inputs.sqrtPriceX96,
            liquidity,
            sellRateCurrent0: testcase.inputs.sellRate0,
            sellRateCurrent1: testcase.inputs.sellRate1,
          }
        )

        expect(divX96(results.sqrtPriceX96)).to.eq(testcase.outputsDivX96.price)
        expect(divX96(results.earningsPool0)).to.eq(testcase.outputsDivX96.amountOut0)
        expect(divX96(results.earningsPool1)).to.eq(testcase.outputsDivX96.amountOut1)
      })
    }

    it('gas', async () => {
      await snapshotGasCost(
        twamm.calculateExecutionUpdates(
          {
            secondsElapsedX96,
            sqrtPriceX96,
            liquidity,
            sellRateCurrent0,
            sellRateCurrent1,
          }
        )
      )
    })

    // TODO:

    it('TWAMM trades pushes the price to the max part of the curve')

    it('TWAMM trades pushes the price to the min part of the curve')

    it('orderPool1 has a 0 sell rate')

    it('orderPool0 has a 0 sell rate')
  })

  describe('#calculateTimeBetweenTicks outputs the correct results when', () => {
    let liquidity: BigNumber
    let sqrtPriceStartX96: BigNumber
    let sqrtPriceEndX96: BigNumber
    let sellRateCurrent0: BigNumber
    let sellRateCurrent1: BigNumber

    beforeEach(() => {
      sqrtPriceStartX96 = encodeSqrtPriceX96(1, 1)
      sqrtPriceEndX96 = encodeSqrtPriceX96(2, 1)
      liquidity = BigNumber.from('1000000000000000000000000')
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('100')
    })

    it('returns the correct result', async () => {
      expect(
        await twamm.callStatic.calculateTimeBetweenTicks(
          liquidity,
          sqrtPriceStartX96,
          sqrtPriceEndX96,
          sellRateCurrent0,
          sellRateCurrent1
        )
        // 333077535900883608001926988272645 / Q96 ~= 4204.029543
      ).to.eq('333077535900883608001926988272645')
    })

    it('gas', async () => {
      await snapshotGasCost(
        twamm.calculateTimeBetweenTicks(
          liquidity,
          sqrtPriceStartX96,
          sqrtPriceEndX96,
          sellRateCurrent0,
          sellRateCurrent1
        )
      )
    })
  })
})
