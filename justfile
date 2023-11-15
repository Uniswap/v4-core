test: test-forge
prep: fix snapshots
snapshots: snapshots-forge

test-forge: install-forge build-forge
    forge test

build-forge: install-forge
    forge build

snapshots-forge: install-forge test-forge
    FOUNDRY_FUZZ_SEED=0x4444 forge snapshot

install-forge:
    forge install

fix:
    forge fmt
