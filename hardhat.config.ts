import 'hardhat-typechain'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'

const importToml = require('import-toml')
const foundryConfig = importToml.sync('foundry.toml')

import { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } from 'hardhat/builtin-tasks/task-names'
import { subtask } from 'hardhat/config'
import { TaskArguments } from 'hardhat/types'
import { join as pathJoin } from 'path'

subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async (args: TaskArguments, hre, runSuper) => {
  if (args.solcVersion !== '0.8.15') {
    throw new Error('need binary for solc version')
  }

  const compilerPath = pathJoin(__dirname, 'bin', 'solc')

  return {
    compilerPath,
    isSolcJs: false,
    version: '0.8.15',
    longVersion: '0.8.15',
  }
})

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      enabledEips: [1153],
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    version: foundryConfig.default.solc_version,
    settings: {
      optimizer: {
        enabled: true,
        runs: foundryConfig.default.optimizer_runs,
      },
      metadata: {
        // do not include the metadata hash, since this is machine dependent
        // and we want all generated code to be deterministic
        // https://docs.soliditylang.org/en/v0.8.15/metadata.html
        bytecodeHash: 'none',
      },
    },
  },
}
