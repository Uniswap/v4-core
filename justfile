
test *args: (test-forge args)
build *args: (build-forge args)
prep *args: fix (test-forge args)


test-forge *args: build-forge
    forge test --isolate --no-match-path 'test/js-scripts/**/*' {{args}}


build-forge *args: install-forge
    forge build --skip 'test/js-scripts/**/*' {{args}}

install-forge:
    forge install

fix:
    forge fmt

