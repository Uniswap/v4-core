"""
Module handling the source unit
Each source unit represents one file so may be associated with
One or more source units are associated with each compilation unit
"""
import re
from typing import Dict, List, Optional, Union, Tuple, TYPE_CHECKING
import cbor2

from Crypto.Hash import keccak

from crytic_compile.utils.naming import Filename
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile.compilation_unit import CompilationUnit


def get_library_candidate(filename: Filename, contract_name: str) -> List[str]:
    """
    Return candidate name for library linking. A candidate is a str that might be found in other bytecodes

    Args:
        filename: filename of the contract
        contract_name: contract name

    Returns:
        The list of candidates
    """

    # Some platform use only the contract name
    # Some use fimename:contract_name

    ret: List[str] = []

    name_with_absolute_filename = filename.absolute + ":" + contract_name
    name_with_used_filename = filename.used + ":" + contract_name

    # Only 36 char were used in the past
    # See https://docs.soliditylang.org/en/develop/using-the-compiler.html#library-linking
    names_candidates = [
        name_with_absolute_filename,
        name_with_absolute_filename[0:36],
        name_with_used_filename,
        name_with_used_filename[0:36],
    ]

    # Solidity 0.4
    ret.append("__" + contract_name + "_" * (38 - len(contract_name)))

    for name_candidate in names_candidates:
        # Solidity 0.4 with filename
        ret.append("__" + name_candidate + "_" * (38 - len(name_candidate)))

        # Solidity 0.5
        sha3_result = keccak.new(digest_bits=256)
        sha3_result.update(name_candidate.encode("utf-8"))
        ret.append("__$" + sha3_result.hexdigest()[:34] + "$__")

    return ret


# pylint: disable=too-many-instance-attributes,too-many-public-methods
class SourceUnit:
    """SourceUnit class"""

    def __init__(self, compilation_unit: "CompilationUnit", filename: Filename):

        self.filename = filename
        self.compilation_unit: "CompilationUnit" = compilation_unit

        # ABI, bytecode and srcmap are indexed by contract_name
        self._abis: Dict = {}
        self._runtime_bytecodes: Dict = {}
        self._init_bytecodes: Dict = {}
        self._hashes: Dict = {}
        self._events: Dict = {}
        self._srcmaps: Dict[str, List[str]] = {}
        self._srcmaps_runtime: Dict[str, List[str]] = {}
        self.ast: Dict = {}

        # Natspec
        self._natspec: Dict[str, Natspec] = {}

        # Libraries used by the contract
        # contract_name -> (library, pattern)
        self._libraries: Dict[str, List[Tuple[str, str]]] = {}

        # set containing all the contract names
        self._contracts_name: List[str] = []

        # set containing all the contract name without the libraries
        self._contracts_name_without_libraries: Optional[List[str]] = None

    # region ABI
    ###################################################################################
    ###################################################################################

    @property
    def abis(self) -> Dict:
        """Return the ABIs

        Returns:
            Dict: ABIs (solc/vyper format) (contract name -> ABI)
        """
        return self._abis

    def abi(self, name: str) -> Dict:
        """Get the ABI from a contract

        Args:
            name (str): Contract name

        Returns:
            Dict: ABI (solc/vyper format)
        """
        return self._abis.get(name, None)

    # endregion
    ###################################################################################
    ###################################################################################
    # region Bytecode
    ###################################################################################
    ###################################################################################

    @property
    def bytecodes_runtime(self) -> Dict[str, str]:
        """Return the runtime bytecodes

        Returns:
            Dict[str, str]: contract => runtime bytecode
        """
        return self._runtime_bytecodes

    @bytecodes_runtime.setter
    def bytecodes_runtime(self, bytecodes: Dict[str, str]) -> None:
        """Set the bytecodes runtime

        Args:
            bytecodes (Dict[str, str]): New bytecodes runtime
        """
        self._runtime_bytecodes = bytecodes

    @property
    def bytecodes_init(self) -> Dict[str, str]:
        """Return the init bytecodes

        Returns:
            Dict[str, str]: contract => init bytecode
        """
        return self._init_bytecodes

    @bytecodes_init.setter
    def bytecodes_init(self, bytecodes: Dict[str, str]) -> None:
        """Set the bytecodes init

        Args:
            bytecodes (Dict[str, str]): New bytecodes init
        """
        self._init_bytecodes = bytecodes

    def bytecode_runtime(self, name: str, libraries: Optional[Dict[str, int]] = None) -> str:
        """Return the runtime bytecode of the contract.
        If library is provided, patch the bytecode

        Args:
            name (str): contract name
            libraries (Optional[Dict[str, str]], optional): lib_name => address. Defaults to None.

        Returns:
            str: runtime bytecode
        """
        runtime = self._runtime_bytecodes.get(name, None)
        return self._update_bytecode_with_libraries(runtime, libraries)

    def bytecode_init(self, name: str, libraries: Optional[Dict[str, int]] = None) -> str:
        """Return the init bytecode of the contract.
        If library is provided, patch the bytecode

        Args:
            name (str): contract name
            libraries (Optional[Dict[str, int]], optional): lib_name => address. Defaults to None.

        Returns:
            str: init bytecode
        """
        init = self._init_bytecodes.get(name, None)
        return self._update_bytecode_with_libraries(init, libraries)

    # endregion
    ###################################################################################
    ###################################################################################
    # region Source mapping
    ###################################################################################
    ###################################################################################

    @property
    def srcmaps_init(self) -> Dict[str, List[str]]:
        """Return the srcmaps init

        Returns:
            Dict[str, List[str]]: Srcmaps init (solc/vyper format)
        """
        return self._srcmaps

    @property
    def srcmaps_runtime(self) -> Dict[str, List[str]]:
        """Return the srcmaps runtime

        Returns:
            Dict[str, List[str]]: Srcmaps runtime (solc/vyper format)
        """
        return self._srcmaps_runtime

    def srcmap_init(self, name: str) -> List[str]:
        """Return the srcmap init of a contract

        Args:
            name (str): name of the contract

        Returns:
            List[str]: Srcmap init (solc/vyper format)
        """
        return self._srcmaps.get(name, [])

    def srcmap_runtime(self, name: str) -> List[str]:
        """Return the srcmap runtime of a contract

        Args:
            name (str): name of the contract

        Returns:
            List[str]: Srcmap runtime (solc/vyper format)
        """
        return self._srcmaps_runtime.get(name, [])

    # endregion
    ###################################################################################
    ###################################################################################
    # region Libraries
    ###################################################################################
    ###################################################################################

    @property
    def libraries(self) -> Dict[str, List[Tuple[str, str]]]:
        """Return the libraries used

        Returns:
            Dict[str, List[Tuple[str, str]]]:  (contract_name -> [(library, pattern))])
        """
        return self._libraries

    def _convert_libraries_names(self, libraries: Dict[str, int]) -> Dict[str, int]:
        """Convert the libraries names
        The name in the argument can be the library name, or filename:library_name
        The returned dict contains all the names possible with the different solc versions

        Args:
            libraries (Dict[str, int]): lib_name => address

        Returns:
            Dict[str, int]: lib_name => address
        """
        new_names = {}
        for (lib, addr) in libraries.items():
            # Prior solidity 0.5
            # libraries were on the format __filename:contract_name_____
            # From solidity 0.5,
            # libraries are on the format __$keccak(filename:contract_name)[34]$__
            # https://solidity.readthedocs.io/en/v0.5.7/050-breaking-changes.html#command-line-and-json-interfaces

            lib_4 = "__" + lib + "_" * (38 - len(lib))

            sha3_result = keccak.new(digest_bits=256)
            sha3_result.update(lib.encode("utf-8"))
            lib_5 = "__$" + sha3_result.hexdigest()[:34] + "$__"

            new_names[lib] = addr
            new_names[lib_4] = addr
            new_names[lib_5] = addr

            for lib_filename, contract_names in self.compilation_unit.filename_to_contracts.items():
                for contract_name in contract_names:
                    if contract_name != lib:
                        continue

                    for candidate in get_library_candidate(lib_filename, lib):
                        new_names[candidate] = addr

        return new_names

    def _library_name_lookup(
        self, lib_name: str, original_contract: str
    ) -> Optional[Tuple[str, str]]:
        """Do a lookup on a library name to its name used in contracts
        The library can be:
        - the original contract name
        - __X__ following Solidity 0.4 format
        - __$..$__ following Solidity 0.5 format

        Args:
            lib_name (str): library name
            original_contract (str): original contract name

        Returns:
            Optional[Tuple[str, str]]: contract_name, library_name
        """

        for filename, contract_names in self.compilation_unit.filename_to_contracts.items():
            for name in contract_names:
                if name == lib_name:
                    return name, name

                for candidate in get_library_candidate(filename, name):
                    if candidate == lib_name:
                        return name, candidate

        # handle specific case of collision for Solidity <0.4
        # We can only detect that the second contract is meant to be the library
        # if there is only two contracts in the codebase
        if len(self._contracts_name) == 2:
            return next(
                (
                    (c, "__" + c + "_" * (38 - len(c)))
                    for c in self._contracts_name
                    if c != original_contract
                ),
                None,
            )

        return None

    def libraries_names(self, name: str) -> List[str]:
        """Return the names of the libraries used by the contract

        Args:
            name (str): contract name

        Returns:
            List[str]: libraries used
        """

        if name not in self._libraries:
            init = re.findall(r"__.{36}__", self.bytecode_init(name))
            runtime = re.findall(r"__.{36}__", self.bytecode_runtime(name))
            libraires = [self._library_name_lookup(x, name) for x in set(init + runtime)]
            self._libraries[name] = [lib for lib in libraires if lib]
        return [name for (name, _) in self._libraries[name]]

    def libraries_names_and_patterns(self, name: str) -> List[Tuple[str, str]]:
        """Return the names and the patterns of the libraries used by the contract

        Args:
            name (str): contract name

        Returns:
            List[Tuple[str, str]]: (lib_name, pattern)
        """

        if name not in self._libraries:
            init = re.findall(r"__.{36}__", self.bytecode_init(name))
            runtime = re.findall(r"__.{36}__", self.bytecode_runtime(name))
            libraires = [self._library_name_lookup(x, name) for x in set(init + runtime)]
            self._libraries[name] = [lib for lib in libraires if lib]
        return self._libraries[name]

    def _update_bytecode_with_libraries(
        self, bytecode: str, libraries: Union[None, Dict[str, int]]
    ) -> str:
        """Update the bytecode with the libraries address

        Args:
            bytecode (str): bytecode to patch
            libraries (Union[None, Dict[str, int]]): pattern => address

        Returns:
            str: Patched bytecode
        """
        if libraries:
            libraries = self._convert_libraries_names(libraries)
            for library_found in re.findall(r"__.{36}__", bytecode):
                if library_found in libraries:
                    bytecode = re.sub(
                        re.escape(library_found),
                        f"{libraries[library_found]:0>40x}",
                        bytecode,
                    )
        return bytecode

    # endregion
    ###################################################################################
    ###################################################################################
    # region Natspec
    ###################################################################################
    ###################################################################################

    @property
    def natspec(self) -> Dict[str, Natspec]:
        """Return the natspec of the contracts

        Returns:
            Dict[str, Natspec]: Contract name -> Natspec
        """
        return self._natspec

    # endregion
    ###################################################################################
    ###################################################################################
    # region Contract Names
    ###################################################################################
    ###################################################################################

    @property
    def contracts_names(self) -> List[str]:
        """Return the contracts names

        Returns:
            List[str]: List of the contracts names
        """
        return self._contracts_name

    @contracts_names.setter
    def contracts_names(self, names: List[str]) -> None:
        """Set the contract names

        Args:
            names (List[str]): New contracts names
        """
        self._contracts_name = names

    def add_contract_name(self, name: str) -> None:
        """Add name to contracts_names, if not already present

        Args:
            name (str): Name to add to the list
        """
        if name not in self.contracts_names:
            self.contracts_names.append(name)

    @property
    def contracts_names_without_libraries(self) -> List[str]:
        """Return the contracts names without the librairies

        Returns:
            List[str]: List of contracts
        """
        if self._contracts_name_without_libraries is None:
            libraries: List[str] = []
            for contract_name in self._contracts_name:
                libraries += self.libraries_names(contract_name)
            self._contracts_name_without_libraries = [
                l for l in self._contracts_name if l not in set(libraries)
            ]
        return self._contracts_name_without_libraries

    # endregion
    ###################################################################################
    ###################################################################################
    # region Hashes
    ###################################################################################
    ###################################################################################

    def hashes(self, name: str) -> Dict[str, int]:
        """Return the hashes of the functions

        Args:
            name (str): contract name

        Returns:
            Dict[str, int]: (function name => signature)
        """
        if not name in self._hashes:
            self._compute_hashes(name)
        return self._hashes[name]

    def _compute_hashes(self, name: str) -> None:
        """Compute the function hashes

        Args:
            name (str): contract name
        """
        self._hashes[name] = {}
        for sig in self.abi(name):
            if "type" in sig:
                if sig["type"] == "function":
                    sig_name = sig["name"]
                    arguments = ",".join([x["type"] for x in sig["inputs"]])
                    sig = f"{sig_name}({arguments})"
                    sha3_result = keccak.new(digest_bits=256)
                    sha3_result.update(sig.encode("utf-8"))
                    self._hashes[name][sig] = int("0x" + sha3_result.hexdigest()[:8], 16)

    # endregion
    ###################################################################################
    ###################################################################################
    # region Events
    ###################################################################################
    ###################################################################################

    def events_topics(self, name: str) -> Dict[str, Tuple[int, List[bool]]]:
        """Return the topics of the contract's events

        Args:
            name (str): contract name

        Returns:
            Dict[str, Tuple[int, List[bool]]]: event signature => topic hash, [is_indexed for each parameter]
        """
        if not name in self._events:
            self._compute_topics_events(name)
        return self._events[name]

    def _compute_topics_events(self, name: str) -> None:
        """Compute the topics of the contract's events

        Args:
            name (str): contract name
        """
        self._events[name] = {}
        for sig in self.abi(name):
            if "type" in sig:
                if sig["type"] == "event":
                    sig_name = sig["name"]
                    arguments = ",".join([x["type"] for x in sig["inputs"]])
                    indexes = [x.get("indexed", False) for x in sig["inputs"]]
                    sig = f"{sig_name}({arguments})"
                    sha3_result = keccak.new(digest_bits=256)
                    sha3_result.update(sig.encode("utf-8"))

                    self._events[name][sig] = (int("0x" + sha3_result.hexdigest()[:8], 16), indexes)

    # endregion
    ###################################################################################
    ###################################################################################
    # region Metadata
    ###################################################################################
    ###################################################################################

    def metadata_of(self, name: str) -> Dict[str, Union[str, bool]]:
        """Return the parsed metadata of a contract by name

        Args:
            name (str): contract name

        Raises:
            ValueError: If no contract/library with that name exists

        Returns:
            Dict[str, Union[str, bool]]: fielname => value
        """
        # the metadata is at the end of the runtime(!) bytecode
        try:
            bytecode = self._runtime_bytecodes[name]
            print("runtime bytecode", bytecode)
        except:
            raise ValueError(  # pylint: disable=raise-missing-from
                f"contract {name} does not exist"
            )

        # the last two bytes contain the length of the preceding metadata.
        metadata_length = int(f"0x{bytecode[-4:]}", base=16)
        # extract the metadata
        metadata = bytecode[-(metadata_length * 2 + 4) :]
        metadata_decoded = cbor2.loads(bytearray.fromhex(metadata))

        for k, v in metadata_decoded.items():
            if len(v) == 1:
                metadata_decoded[k] = bool(v)
            elif k == "solc":
                metadata_decoded[k] = ".".join([str(d) for d in v])
            else:
                # there might be nested items or other unforeseen errors
                try:
                    metadata_decoded[k] = v.hex()
                except:  # pylint: disable=bare-except
                    pass

        return metadata_decoded

    def remove_metadata(self) -> None:
        """Remove init bytecode
        See
        http://solidity.readthedocs.io/en/v0.4.24/metadata.html#encoding-of-the-metadata-hash-in-the-bytecode
        """
        # the metadata is at the end of the runtime(!) bytecode of each contract
        for (key, bytecode) in self._runtime_bytecodes.items():
            if not bytecode or bytecode == "0x":
                continue
            # the last two bytes contain the length of the preceding metadata.
            metadata_length = int(f"0x{bytecode[-4:]}", base=16)
            # store the metadata here so we can remove it from the init bytecode later on
            metadata = bytecode[-(metadata_length * 2 + 4) :]
            # remove the metadata from the runtime bytecode, '+ 4' for the two length-indication bytes at the end
            self._runtime_bytecodes[key] = bytecode[0 : -(metadata_length * 2 + 4)]
            # remove the metadata from the init bytecode
            self._init_bytecodes[key] = self._init_bytecodes[key].replace(metadata, "")

    # endregion
    ###################################################################################
    ###################################################################################
