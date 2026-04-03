/// A spec to allow implementations of unlock callback to be called.
/// If one imports this spec file, it is mandatory to have at least one implementation
/// of the unlockCallback(bytes) function in the contracts scene of the Prover. 
methods {
    // IUnlockCallback
    function _.unlockCallback(bytes data) external => DISPATCHER(true);
}