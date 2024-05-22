test: test-forge
prep: fix

test-mt TEST: install-forge build-forge
    forge test --mt {{TEST}} --isolate --no-match-path 'test/js-scripts/**/*'

test-forge: install-forge build-forge
    forge test --isolate --no-match-path 'test/js-scripts/**/*' 


build-forge: install-forge
    forge build --skip 'test/js-scripts/**/*'

install-forge:
    forge install

fix:
    forge fmt

