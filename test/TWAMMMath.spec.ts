import { TWAMMTest } from '../typechain/TWAMMTest'
import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, MaxUint128, MAX_SQRT_RATIO } from './shared/utilities'

function toWei(n: string): BigNumber {
  return ethers.utils.parseEther(n)
}

function divX96(n: BigNumber): string {
  return (parseInt(n.toString()) / 2 ** 96).toFixed(7).toString()
}

// TODO: fix precision in quad lib, should be
// MAX_SQRT_PRICE
const MAX_WITH_LOSS = BigNumber.from('1461446703485210103287273052203988790139028504575')

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

    const fixedPoint = BigNumber.from(2).pow(96)

    beforeEach(async () => {
      secondsElapsedX96 = BigNumber.from(3600).mul(fixedPoint)
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
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96: testcase.inputs.sqrtPriceX96,
          liquidity,
          sellRateCurrent0: testcase.inputs.sellRate0,
          sellRateCurrent1: testcase.inputs.sellRate1,
        })

        expect(divX96(results.sqrtPriceX96)).to.eq(testcase.outputsDivX96.price)
        expect(divX96(results.earningsPool0)).to.eq(testcase.outputsDivX96.amountOut0)
        expect(divX96(results.earningsPool1)).to.eq(testcase.outputsDivX96.amountOut1)
      })
    }

    it('gas', async () => {
      await snapshotGasCost(
        twamm.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
      )
    })

    // TODO: Calculating the time to p_target (required when we reach the max price) does not work when we push the price to an edge.
    // Desmos also shows undefined or negative so may need a new formula here?
    it.skip('TWAMM trades against itself when low liquidity', async () => {
      // set low liquidity to push price
      liquidity = '1000000000000000000'

      sellRateCurrent0 = toWei('10')
      sellRateCurrent1 = toWei('1')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })

      expect(results.sqrtPriceX96).to.eq(MAX_WITH_LOSS)

      const expectedAmount = sellRateCurrent0.mul(secondsElapsedX96).div(fixedPoint)
      console.log(expectedAmount.toString())

      // the trades should be slightly greater than the expectedAmount?
      expect(results.earningsAmount0).to.eq(expectedAmount)
      expect(results.earningsAmount1).to.eq(expectedAmount)
    })

    it.skip('TWAMM trades pushes the price to the max part of the curve', async () => {
      // set low liquidity
      liquidity = '1000000'
      // to push price to max part of the curve, sell lots of token1
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('4')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })
      // twamm is trading with itself bc liquidity low
      const expectedAmount0 = sellRateCurrent1.mul(secondsElapsedX96).div(fixedPoint)
      const expectedAmount1 = sellRateCurrent0.mul(secondsElapsedX96).div(fixedPoint)

      expect(results.sqrtPriceX96).to.eq(MAX_WITH_LOSS)
      expect(results.earningsAmount0).to.eq(expectedAmount0)
      expect(results.earningsAmount1).to.eq(expectedAmount1)
    })

    // TODO: Even though the price should fall to the min, it overflows.
    it.skip('TWAMM trades pushes the price to the min part of the curve', async () => {
      // set low liquidity
      liquidity = '100000000000000000000'
      // todo to push price to lowest part of the curve, sell lots of token0
      sellRateCurrent0 = toWei('30000')
      sellRateCurrent1 = toWei('1')

      console.log(sqrtPriceX96.toString())

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })

      const expectedAmount0 = sellRateCurrent1.mul(secondsElapsedX96).div(fixedPoint)
      const expectedAmount1 = sellRateCurrent0.mul(secondsElapsedX96).div(fixedPoint)

      expect(results.sqrtPriceX96).to.eq(MAX_WITH_LOSS)
      // expect(results.earningsAmount0).to.eq(expectedAmount0)
      // expect(results.earningsAmount1).to.eq(expectedAmount1)
    })

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
