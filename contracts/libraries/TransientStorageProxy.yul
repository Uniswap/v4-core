object "TransientStorageProxy" {
  code {
      // just creates the runtime code
      let size := datasize("runtime")
      datacopy(0, dataoffset("runtime"), size)
      return(0, size)
  }

  object "runtime" {
      code {
          switch calldatasize()
          case 32 {
            mstore(0, tload(calldataload(0)))
            return(0, 32)
          }
          case 64 {
            tstore(calldataload(0), calldataload(32))
          }
          default {
            revert(0, 0)
          }
      }
  }
}