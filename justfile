solc_file := if os() == "macos" { "./bin/solc-mac" } else { "./bin/solc-static-linux" }

test: test-forge
prep: fix snapshots

test-forge: install-forge build-forge
    forge test --use {{ solc_file }}

build-forge: install-forge
    forge build --use {{ solc_file }}

install-forge:
    forge install

fix:
    forge fmt
