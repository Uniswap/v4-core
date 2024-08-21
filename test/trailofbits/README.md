# Stateful Property Test Suite

TODO: Add link to the audit report appendix.

`export FOUNDRY_PROFILE=statefulfuzz`


To test the Actions harness, use `forge test --match-contract ActionsHarness_Test -vvv`

To run the Actions harness, install Medusa or Echidna, then use:

`forge clean && forge build --build-info && medusa fuzz`

`echidna ./test/trailofbits/ActionFuzzEntrypoint.sol --contract ActionFuzzEntrypoint --config ./echidna.config.yml`


## Sequence Diagram for Actions harness


![Sequence Diagram for Actions harness](./SequenceDiagram.svg)