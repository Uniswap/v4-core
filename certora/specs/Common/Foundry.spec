/// Foundry integration in CVL basic spec.
/// For documentation, go to https://github.com/Certora/Examples/tree/cli-beta/FoundryIntegration.
//override function init_fuzz_tests(method f, env e) {
// 
//}
use rule verify_fuzz_tests_no_revert;
use rule verify_fuzz_tests;