import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { MaxUint128 } from './shared/utilities'

describe.only('TWAMM', () => {
  let wallet: Wallet, other: Wallet

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy()) as TWAMMTest
  }

  describe('#submitLongTermOrder', () => {
    let twamm: TWAMMTest
    beforeEach('deploy test twamm', async () => {
      twamm = await loadFixture(twammFixture)
    })

		it('loads the fixture', async () => {
			const expiration = ((await ethers.provider.getBlock('latest')).timestamp) + 86400
			const tx = await twamm.submitLongTermOrder({
				zeroForOne: true,
				owner: wallet.address,
				amountIn: `1${'0'.repeat(18)}`,
				expiration
			})
			const receipt = await tx.wait()
			console.log(receipt.events![0]!.args)
		})
	})
})
