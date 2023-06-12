test: test-forge test-hardhat
prep: fix snapshots
snapshots: snapshots-forge snapshots-hardhat

test-forge: install-forge build-forge
    forge test

test-hardhat: install-hardhat
    yarn test

build-forge: install-forge
    forge build

build-hardhat: install-hardhat
    yarn build

snapshots-forge: install-forge
    forge snapshot

snapshots-hardhat: install-hardhat
    yarn snapshots

install-forge:
    forge install

install-hardhat:
    yarn install

fix:
    forge fmt
