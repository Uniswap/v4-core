"""
Etherscan platform.
"""

import json
import logging
import os
import re
import urllib.request
from json.decoder import JSONDecodeError
from pathlib import Path, PurePosixPath
from typing import TYPE_CHECKING, Dict, List, Union, Tuple, Optional

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform import solc_standard_json
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import Filename

# Cycle dependency

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


ETHERSCAN_BASE = "https://api%s/api?module=contract&action=getsourcecode&address=%s"

ETHERSCAN_BASE_BYTECODE = "https://%s/address/%s#code"

SUPPORTED_NETWORK = {
    # Key, (prefix_base, perfix_bytecode)
    "mainet:": (".etherscan.io", "etherscan.io"),
    "optim:": ("-optimistic.etherscan.io", "optimistic.etherscan.io"),
    "goerli:": ("-goerli.etherscan.io", "goerli.etherscan.io"),
    "sepolia:": ("-sepolia.etherscan.io", "sepolia.etherscan.io"),
    "tobalaba:": ("-tobalaba.etherscan.io", "tobalaba.etherscan.io"),
    "bsc:": (".bscscan.com", "bscscan.com"),
    "testnet.bsc:": ("-testnet.bscscan.com", "testnet.bscscan.com"),
    "arbi:": (".arbiscan.io", "arbiscan.io"),
    "testnet.arbi:": ("-testnet.arbiscan.io", "testnet.arbiscan.io"),
    "poly:": (".polygonscan.com", "polygonscan.com"),
    "mumbai:": ("-testnet.polygonscan.com", "testnet.polygonscan.com"),
    "avax:": (".snowtrace.io", "snowtrace.io"),
    "testnet.avax:": ("-testnet.snowtrace.io", "testnet.snowtrace.io"),
    "ftm:": (".ftmscan.com", "ftmscan.com"),
    "goerli.base:": ("-goerli.basescan.org", "goerli.basescan.org"),
    "base:": (".basescan.org", "basescan.org"),
    "gno:": (".gnosisscan.io", "gnosisscan.io"),
    "polyzk:": ("-zkevm.polygonscan.com", "zkevm.polygonscan.com"),
    "blast:": (".blastscan.io", "blastscan.io"),
}


def _handle_bytecode(crytic_compile: "CryticCompile", target: str, result_b: bytes) -> None:
    """Parse the bytecode and populate CryticCompile info

    Args:
        crytic_compile (CryticCompile): Associate CryticCompile object
        target (str): path to the target
        result_b (bytes): text containing the bytecode
    """

    # There is no direct API to get the bytecode from etherscan
    # The page changes from time to time, we use for now a simple parsing, it will not be robust
    begin = """Search Algorithm">\nSimilar Contracts</button>\n"""
    begin += """<div id="dividcode">\n<pre class=\'wordwrap\' style=\'height: 15pc;\'>0x"""
    result = result_b.decode("utf8")
    # Removing everything before the begin string
    result = result[result.find(begin) + len(begin) :]
    bytecode = result[: result.find("<")]

    contract_name = f"Contract_{target}"

    contract_filename = Filename(absolute="", relative="", short="", used="")

    compilation_unit = CompilationUnit(crytic_compile, str(target))

    source_unit = compilation_unit.create_source_unit(contract_filename)

    source_unit.add_contract_name(contract_name)
    compilation_unit.filename_to_contracts[contract_filename].add(contract_name)
    source_unit.abis[contract_name] = {}
    source_unit.bytecodes_init[contract_name] = bytecode
    source_unit.bytecodes_runtime[contract_name] = ""
    source_unit.srcmaps_init[contract_name] = []
    source_unit.srcmaps_runtime[contract_name] = []

    compilation_unit.compiler_version = CompilerVersion(
        compiler="unknown", version="", optimized=False
    )

    crytic_compile.bytecode_only = True


def _handle_single_file(
    source_code: str, addr: str, prefix: Optional[str], contract_name: str, export_dir: str
) -> str:
    """Handle a result with a single file

    Args:
        source_code (str): source code
        addr (str): contract address
        prefix (Optional[str]): used to separate different chains
        contract_name (str): contract name
        export_dir (str): directory where the code will be saved

    Returns:
        str: filename containing the source code
    """
    if prefix:
        filename = os.path.join(export_dir, f"{addr}{prefix}-{contract_name}.sol")
    else:
        filename = os.path.join(export_dir, f"{addr}-{contract_name}.sol")

    with open(filename, "w", encoding="utf8") as file_desc:
        file_desc.write(source_code)

    return filename


def _handle_multiple_files(
    dict_source_code: Dict, addr: str, prefix: Optional[str], contract_name: str, export_dir: str
) -> Tuple[List[str], str, Optional[List[str]]]:
    """Handle a result with a multiple files. Generate multiple Solidity files

    Args:
        dict_source_code (Dict): dict result from etherscan
        addr (str): contract address
        prefix (Optional[str]): used to separate different chains
        contract_name (str): contract name
        export_dir (str): directory where the code will be saved

    Returns:
        Tuple[List[str], str]: filesnames, directory, where target_filename is the main file

    Raises:
        IOError: if the path is outside of the allowed directory
    """
    if prefix:
        directory = os.path.join(export_dir, f"{addr}{prefix}-{contract_name}")
    else:
        directory = os.path.join(export_dir, f"{addr}-{contract_name}")

    if "sources" in dict_source_code:
        # etherscan might return an object with a sources prop, which contains an object with contract names as keys
        source_codes = dict_source_code["sources"]
    else:
        # or etherscan might return an object with contract names as keys
        source_codes = dict_source_code

    filtered_paths: List[str] = []
    for filename, source_code in source_codes.items():
        path_filename = PurePosixPath(filename)
        # Only keep solidity files
        if path_filename.suffix not in [".sol", ".vy"]:
            continue

        # https://etherscan.io/address/0x19bb64b80cbf61e61965b0e5c2560cc7364c6546#code has an import of erc721a/contracts/ERC721A.sol
        # if the full path is lost then won't compile
        if "contracts" == path_filename.parts[0] and not filename.startswith("@"):
            path_filename = PurePosixPath(
                *path_filename.parts[path_filename.parts.index("contracts") :]
            )

        # Convert "absolute" paths such as "/interfaces/IFoo.sol" into relative ones.
        # This is needed due to the following behavior from pathlib.Path:
        # > When several absolute paths are given, the last is taken as an anchor
        # We need to make sure this is relative, so that Path(directory, ...) remains anchored to directory
        if path_filename.is_absolute():
            path_filename = PurePosixPath(*path_filename.parts[1:])

        filtered_paths.append(path_filename.as_posix())
        path_filename_disk = Path(directory, path_filename)

        allowed_path = os.path.abspath(directory)
        if os.path.commonpath((allowed_path, os.path.abspath(path_filename_disk))) != allowed_path:
            raise IOError(
                f"Path '{path_filename_disk}' is outside of the allowed directory: {allowed_path}"
            )
        if not os.path.exists(path_filename_disk.parent):
            os.makedirs(path_filename_disk.parent)
        with open(path_filename_disk, "w", encoding="utf8") as file_desc:
            file_desc.write(source_code["content"])

    remappings = dict_source_code.get("settings", {}).get("remappings", None)

    return list(filtered_paths), directory, _sanitize_remappings(remappings, directory)


class Etherscan(AbstractPlatform):
    """
    Etherscan platform
    """

    NAME = "Etherscan"
    PROJECT_URL = "https://etherscan.io/"
    TYPE = Type.ETHERSCAN

    # pylint: disable=too-many-locals,too-many-branches,too-many-statements
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Run the compilation

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile object
            **kwargs: optional arguments. Used "solc", "etherscan_only_source_code", "etherscan_only_bytecode",
                "etherscan_api_key", "export_dir"

        Raises:
            InvalidCompilation: if etherscan returned an error, or its results were not correctly parsed
        """

        target = self._target

        if target.startswith(tuple(SUPPORTED_NETWORK)):
            prefix: Union[None, str] = SUPPORTED_NETWORK[target[: target.find(":") + 1]][0]
            prefix_bytecode = SUPPORTED_NETWORK[target[: target.find(":") + 1]][1]
            addr = target[target.find(":") + 1 :]
            etherscan_url = ETHERSCAN_BASE % (prefix, addr)
            etherscan_bytecode_url = ETHERSCAN_BASE_BYTECODE % (prefix_bytecode, addr)

        else:
            etherscan_url = ETHERSCAN_BASE % (".etherscan.io", target)
            etherscan_bytecode_url = ETHERSCAN_BASE_BYTECODE % ("etherscan.io", target)
            addr = target
            prefix = None

        only_source = kwargs.get("etherscan_only_source_code", False)
        only_bytecode = kwargs.get("etherscan_only_bytecode", False)

        etherscan_api_key = kwargs.get("etherscan_api_key", None)
        arbiscan_api_key = kwargs.get("arbiscan_api_key", None)
        polygonscan_api_key = kwargs.get("polygonscan_api_key", None)
        test_polygonscan_api_key = kwargs.get("test_polygonscan_api_key", None)
        avax_api_key = kwargs.get("avax_api_key", None)
        ftmscan_api_key = kwargs.get("ftmscan_api_key", None)
        bscan_api_key = kwargs.get("bscan_api_key", None)
        optim_api_key = kwargs.get("optim_api_key", None)
        base_api_key = kwargs.get("base_api_key", None)
        gno_api_key = kwargs.get("gno_api_key", None)
        polyzk_api_key = kwargs.get("polyzk_api_key", None)
        blast_api_key = kwargs.get("blast_api_key", None)

        export_dir = kwargs.get("export_dir", "crytic-export")
        export_dir = os.path.join(
            export_dir, kwargs.get("etherscan_export_dir", "etherscan-contracts")
        )

        if etherscan_api_key and "etherscan" in etherscan_url:
            etherscan_url += f"&apikey={etherscan_api_key}"
            etherscan_bytecode_url += f"&apikey={etherscan_api_key}"
        if arbiscan_api_key and "arbiscan" in etherscan_url:
            etherscan_url += f"&apikey={arbiscan_api_key}"
            etherscan_bytecode_url += f"&apikey={arbiscan_api_key}"
        if polygonscan_api_key and "polygonscan" in etherscan_url:
            etherscan_url += f"&apikey={polygonscan_api_key}"
            etherscan_bytecode_url += f"&apikey={polygonscan_api_key}"
        if test_polygonscan_api_key and "polygonscan" in etherscan_url:
            etherscan_url += f"&apikey={test_polygonscan_api_key}"
            etherscan_bytecode_url += f"&apikey={test_polygonscan_api_key}"
        if avax_api_key and "snowtrace" in etherscan_url:
            etherscan_url += f"&apikey={avax_api_key}"
            etherscan_bytecode_url += f"&apikey={avax_api_key}"
        if ftmscan_api_key and "ftmscan" in etherscan_url:
            etherscan_url += f"&apikey={ftmscan_api_key}"
            etherscan_bytecode_url += f"&apikey={ftmscan_api_key}"
        if bscan_api_key and "bscscan" in etherscan_url:
            etherscan_url += f"&apikey={bscan_api_key}"
            etherscan_bytecode_url += f"&apikey={bscan_api_key}"
        if optim_api_key and "optim" in etherscan_url:
            etherscan_url += f"&apikey={optim_api_key}"
            etherscan_bytecode_url += f"&apikey={optim_api_key}"
        if base_api_key and "base" in etherscan_url:
            etherscan_url += f"&apikey={base_api_key}"
            etherscan_bytecode_url += f"&apikey={base_api_key}"
        if gno_api_key and "gno" in etherscan_url:
            etherscan_url += f"&apikey={gno_api_key}"
            etherscan_bytecode_url += f"&apikey={gno_api_key}"
        if polyzk_api_key and "zkevm" in etherscan_url:
            etherscan_url += f"&apikey={polyzk_api_key}"
            etherscan_bytecode_url += f"&apikey={polyzk_api_key}"
        if blast_api_key and "blast" in etherscan_url:
            etherscan_url += f"&apikey={blast_api_key}"
            etherscan_bytecode_url += f"&apikey={blast_api_key}"

        source_code: str = ""
        result: Dict[str, Union[bool, str, int]] = {}
        contract_name: str = ""

        if not only_bytecode:
            if "polygon" in etherscan_url or "basescan" in etherscan_url:
                # build object with headers, then send request
                new_etherscan_url = urllib.request.Request(
                    etherscan_url, headers={"User-Agent": "Mozilla/5.0"}
                )
                with urllib.request.urlopen(new_etherscan_url) as response:
                    html = response.read()
            else:
                with urllib.request.urlopen(etherscan_url) as response:
                    html = response.read()

            info = json.loads(html)

            if (
                "result" in info
                and "rate limit reached" in info["result"]
                and "message" in info
                and info["message"] == "NOTOK"
            ):
                LOGGER.error("Etherscan API rate limit exceeded")
                raise InvalidCompilation("Etherscan API rate limit exceeded")

            if "message" not in info:
                LOGGER.error("Incorrect etherscan request")
                raise InvalidCompilation("Incorrect etherscan request " + etherscan_url)

            if not info["message"].startswith("OK") and "Invalid API Key" in info["result"]:
                LOGGER.error("Invalid etherscan API Key")
                raise InvalidCompilation("Invalid etherscan API Key: " + etherscan_url)

            if not info["message"].startswith("OK"):
                LOGGER.error("Contract has no public source code")
                raise InvalidCompilation("Contract has no public source code: " + etherscan_url)

            if "result" not in info:
                LOGGER.error("Contract has no public source code")
                raise InvalidCompilation("Contract has no public source code: " + etherscan_url)

            result = info["result"][0]
            # Assert to help mypy
            assert isinstance(result["SourceCode"], str)
            assert isinstance(result["ContractName"], str)
            source_code = result["SourceCode"]
            contract_name = result["ContractName"]

        if source_code == "" and not only_source:
            LOGGER.info("Source code not available, try to fetch the bytecode only")

            req = urllib.request.Request(
                etherscan_bytecode_url, headers={"User-Agent": "Mozilla/5.0"}
            )
            with urllib.request.urlopen(req) as response:
                html = response.read()

            _handle_bytecode(crytic_compile, target, html)
            return

        if source_code == "":
            LOGGER.error("Contract has no public source code")
            raise InvalidCompilation("Contract has no public source code: " + etherscan_url)

        if not os.path.exists(export_dir):
            os.makedirs(export_dir)

        # Assert to help mypy
        assert isinstance(result["CompilerVersion"], str)

        compiler_version = re.findall(
            r"\d+\.\d+\.\d+", _convert_version(result["CompilerVersion"])
        )[0]

        # etherscan can report "default" which is not a valid EVM version
        evm_version: Optional[str] = None
        if "EVMVersion" in result:
            assert isinstance(result["EVMVersion"], str)
            evm_version = result["EVMVersion"] if result["EVMVersion"] != "Default" else None

        optimization_used: bool = result["OptimizationUsed"] == "1"

        optimize_runs = None
        if optimization_used:
            optimize_runs = int(result["Runs"])

        working_dir: Optional[str] = None
        remappings: Optional[List[str]] = None

        dict_source_code: Optional[Dict] = None
        try:
            # etherscan might return an object with two curly braces, {{ content }}
            dict_source_code = json.loads(source_code[1:-1])
            assert isinstance(dict_source_code, dict)
            filenames, working_dir, remappings = _handle_multiple_files(
                dict_source_code, addr, prefix, contract_name, export_dir
            )
        except JSONDecodeError:
            try:
                # or etherscan might return an object with single curly braces, { content }
                dict_source_code = json.loads(source_code)
                assert isinstance(dict_source_code, dict)
                filenames, working_dir, remappings = _handle_multiple_files(
                    dict_source_code, addr, prefix, contract_name, export_dir
                )
            except JSONDecodeError:
                filenames = [
                    _handle_single_file(source_code, addr, prefix, contract_name, export_dir)
                ]

        # viaIR is not exposed on the top level JSON offered by etherscan, so we need to inspect the settings
        via_ir_enabled: Optional[bool] = None
        if isinstance(dict_source_code, dict):
            via_ir_enabled = dict_source_code.get("settings", {}).get("viaIR", None)

        compilation_unit = CompilationUnit(crytic_compile, contract_name)

        compilation_unit.compiler_version = CompilerVersion(
            compiler=kwargs.get("solc", "solc"),
            version=compiler_version,
            optimized=optimization_used,
            optimize_runs=optimize_runs,
        )
        compilation_unit.compiler_version.look_for_installed_version()

        if "Proxy" in result and result["Proxy"] == "1":
            assert "Implementation" in result
            implementation = str(result["Implementation"])
            if target.startswith(tuple(SUPPORTED_NETWORK)):
                implementation = f"{target[:target.find(':')]}:{implementation}"
            compilation_unit.implementation_address = implementation

        solc_standard_json.standalone_compile(
            filenames,
            compilation_unit,
            working_dir=working_dir,
            remappings=remappings,
            evm_version=evm_version,
            via_ir=via_ir_enabled,
        )

        metadata_config = {
            "solc_remaps": remappings if remappings else {},
            "solc_solcs_select": compiler_version,
            "solc_args": " ".join(
                filter(
                    None,
                    [
                        "--via-ir" if via_ir_enabled else "",
                        "--optimize --optimize-runs " + str(optimize_runs) if optimize_runs else "",
                        "--evm-version " + evm_version if evm_version else "",
                    ],
                )
            ),
        }

        with open(
            os.path.join(working_dir if working_dir else export_dir, "crytic_compile.config.json"),
            "w",
            encoding="utf-8",
        ) as f:
            json.dump(metadata_config, f)

    def clean(self, **_kwargs: str) -> None:
        pass

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a etherscan project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used "etherscan_ignore"

        Returns:
            bool: True if the target is a etherscan project
        """
        etherscan_ignore = kwargs.get("etherscan_ignore", False)
        if etherscan_ignore:
            return False
        if target.startswith(tuple(SUPPORTED_NETWORK)):
            target = target[target.find(":") + 1 :]
        return bool(re.match(r"^\s*0x[a-zA-Z0-9]{40}\s*$", target))

    def is_dependency(self, _path: str) -> bool:
        """Check if the path is a dependency

        Args:
            _path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        return False

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return []


def _convert_version(version: str) -> str:
    """Convert the compiler version

    Args:
        version (str): original version

    Returns:
        str: converted version
    """
    if "+" in version:
        return version[1 : version.find("+")]
    return version[1:]


def _sanitize_remappings(
    remappings: Optional[List[str]], allowed_directory: str
) -> Optional[List[str]]:
    """Sanitize a list of remappings

    Args:
        remappings: (Optional[List[str]]): a list of remappings
        allowed_directory: the allowed base directory for remaps

    Returns:
        Optional[List[str]]: a list of sanitized remappings
    """

    if remappings is None:
        return remappings

    allowed_path = os.path.abspath(allowed_directory)

    remappings_clean: List[str] = []
    for r in remappings:
        split = r.split("=", 2)
        if len(split) != 2:
            LOGGER.warning("Invalid remapping %s", r)
            continue

        origin, dest = split[0], PurePosixPath(split[1])

        # if path is absolute, relativize it
        if dest.is_absolute():
            dest = PurePosixPath(*dest.parts[1:])

        dest_disk = Path(allowed_directory, dest)

        if os.path.commonpath((allowed_path, os.path.abspath(dest_disk))) != allowed_path:
            LOGGER.warning("Remapping %s=%s is potentially unsafe, skipping", origin, dest)
            continue

        # always use a trailing slash for the destination
        remappings_clean.append(f"{origin}={str(dest / '_')[:-1]}")

    return remappings_clean
