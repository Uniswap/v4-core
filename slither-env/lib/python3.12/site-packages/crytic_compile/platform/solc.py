"""
Solc platform
"""
import json
import logging
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Optional, Union, Any

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import (
    combine_filename_name,
    convert_filename,
    extract_filename,
    extract_name,
)

# Cycle dependency
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


def _build_contract_data(compilation_unit: "CompilationUnit") -> Dict:
    contracts = {}

    libraries_to_update = compilation_unit.crytic_compile.libraries

    for filename, source_unit in compilation_unit.source_units.items():
        for contract_name in source_unit.contracts_names:
            libraries = source_unit.libraries_names_and_patterns(contract_name)
            abi = str(source_unit.abi(contract_name))
            abi = abi.replace("'", '"')
            abi = abi.replace("True", "true")
            abi = abi.replace("False", "false")
            abi = abi.replace(" ", "")
            exported_name = combine_filename_name(filename.absolute, contract_name)
            contracts[exported_name] = {
                "srcmap": ";".join(source_unit.srcmap_init(contract_name)),
                "srcmap-runtime": ";".join(source_unit.srcmap_runtime(contract_name)),
                "abi": abi,
                "bin": source_unit.bytecode_init(contract_name, libraries_to_update),
                "bin-runtime": source_unit.bytecode_runtime(contract_name, libraries_to_update),
                "userdoc": source_unit.natspec[contract_name].userdoc.export(),
                "devdoc": source_unit.natspec[contract_name].devdoc.export(),
                "libraries": dict(libraries) if libraries else {},
            }
    return contracts


def export_to_solc_from_compilation_unit(
    compilation_unit: "CompilationUnit", key: str, export_dir: str
) -> Optional[str]:
    """Export the compilation unit to the standard solc output format.
    The exported file will be $key.json

    Args:
        compilation_unit (CompilationUnit): Compilation unit to export
        key (str): Filename Id
        export_dir (str): Export directory

    Returns:
        Optional[str]: path to the file generated
    """
    contracts = _build_contract_data(compilation_unit)

    # Create additional informational objects.
    sources = {filename: {"AST": ast} for (filename, ast) in compilation_unit.asts.items()}
    source_list = [x.absolute for x in compilation_unit.filenames]

    # Create our root object to contain the contracts and other information.
    output = {"sources": sources, "sourceList": source_list, "contracts": contracts}

    # If we have an export directory specified, we output the JSON.
    if export_dir:
        if not os.path.exists(export_dir):
            os.makedirs(export_dir)
        path = os.path.join(export_dir, f"{key}.json")

        with open(path, "w", encoding="utf8") as file_desc:
            json.dump(output, file_desc)
        return path
    return None


def export_to_solc(crytic_compile: "CryticCompile", **kwargs: str) -> List[str]:
    """Export all the compilation units to the standard solc output format.
    The files generated will be either
    - combined_solc.json, if there is one compilation unit (echidna legacy)
    - $key.json, where $key is the compilation unit identifiant

    Args:
        crytic_compile (CryticCompile): CryticCompile object to export
        **kwargs: optional arguments. Used: "export_dir"

    Returns:
        List[str]: List of filenames generated
    """
    # Obtain objects to represent each contract
    export_dir = kwargs.get("export_dir", "crytic-export")

    if len(crytic_compile.compilation_units) == 1:
        compilation_unit = list(crytic_compile.compilation_units.values())[0]
        path = export_to_solc_from_compilation_unit(compilation_unit, "combined_solc", export_dir)
        if path:
            return [path]
        return []

    paths = []
    for key, compilation_unit in crytic_compile.compilation_units.items():
        path = export_to_solc_from_compilation_unit(compilation_unit, key, export_dir)
        if path:
            paths.append(path)
    return paths


class Solc(AbstractPlatform):
    """
    Solc platform
    """

    NAME = "solc"
    PROJECT_URL = "https://github.com/ethereum/solidity"
    TYPE = Type.SOLC

    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Run the compilation

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile object
            **kwargs: optional arguments. Used: "solc_working_dir", "solc_force_legacy_json"

        Raises:
            InvalidCompilation: If solc failed to run
        """

        solc_working_dir = kwargs.get("solc_working_dir", None)
        force_legacy_json = kwargs.get("solc_force_legacy_json", False)
        compilation_unit = CompilationUnit(crytic_compile, str(self._target))

        targets_json = _get_targets_json(compilation_unit, self._target, **kwargs)

        # there have been a couple of changes in solc starting from 0.8.x,
        if force_legacy_json and _is_at_or_above_minor_version(compilation_unit, 8):
            raise InvalidCompilation("legacy JSON not supported from 0.8.x onwards")

        skip_filename = compilation_unit.compiler_version.version in [
            f"0.4.{x}" for x in range(0, 10)
        ]

        if "sources" in targets_json:
            for path, info in targets_json["sources"].items():
                if skip_filename:
                    path = convert_filename(
                        self._target,
                        relative_to_short,
                        crytic_compile,
                        working_dir=solc_working_dir,
                    )
                else:
                    path = convert_filename(
                        path, relative_to_short, crytic_compile, working_dir=solc_working_dir
                    )
                source_unit = compilation_unit.create_source_unit(path)
                source_unit.ast = info["AST"]

        solc_handle_contracts(
            targets_json, skip_filename, compilation_unit, self._target, solc_working_dir
        )

    def clean(self, **_kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **_kwargs: unused.
        """
        return

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a Solidity file

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Not used

        Returns:
            bool: True if the target is a Solidity file
        """
        return os.path.isfile(target) and target.endswith(".sol")

    def is_dependency(self, _path: str) -> bool:
        """Check if the path is a dependency (always false for direct solc)

        Args:
            _path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        return False

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands (always empty for direct solc)

        Returns:
            List[str]: The guessed unit tests commands
        """
        return []


def _get_targets_json(compilation_unit: "CompilationUnit", target: str, **kwargs: Any) -> Dict:
    """Run the compilation, population the compilation info, and returns the json compilation artifacts

    Args:
        compilation_unit (CompilationUnit): Compilation unit
        target (str): path to the solidity file
        **kwargs: optional arguments. Used: "solc", "solc_disable_warnings", "solc_args", "solc_remaps",
            "solc_solcs_bin", "solc_solcs_select", "solc_working_dir", "solc_force_legacy_json"

    Returns:
        Dict: Json of the compilation artifacts
    """
    solc: str = kwargs.get("solc", "solc")
    solc_disable_warnings: bool = kwargs.get("solc_disable_warnings", False)
    solc_arguments: str = kwargs.get("solc_args", "")
    solc_remaps: Optional[Union[str, List[str]]] = kwargs.get("solc_remaps", None)
    # From config file, solcs is a dict (version -> path)
    # From command line, solc is a list
    # The guessing of version only works from config file
    # This is to prevent too complex command line
    solcs_path_: Optional[Union[str, Dict, List[str]]] = kwargs.get("solc_solcs_bin")
    solcs_path: Optional[Union[Dict, List[str]]] = None
    if solcs_path_:
        if isinstance(solcs_path_, str):
            solcs_path = solcs_path_.split(",")
        else:
            solcs_path = solcs_path_
    # solcs_env is always a list. It matches solc-select list
    solcs_env = kwargs.get("solc_solcs_select")
    solc_working_dir = kwargs.get("solc_working_dir", None)
    force_legacy_json = kwargs.get("solc_force_legacy_json", False)

    if solcs_path:
        return _run_solcs_path(
            compilation_unit,
            target,
            solcs_path,
            solc_disable_warnings,
            solc_arguments,
            solc_remaps=solc_remaps,
            working_dir=solc_working_dir,
            force_legacy_json=force_legacy_json,
        )

    if solcs_env:
        solcs_env_list = solcs_env.split(",")
        return _run_solcs_env(
            compilation_unit,
            target,
            solc,
            solc_disable_warnings,
            solc_arguments,
            solcs_env=solcs_env_list,
            solc_remaps=solc_remaps,
            working_dir=solc_working_dir,
            force_legacy_json=force_legacy_json,
        )

    return _run_solc(
        compilation_unit,
        target,
        solc,
        solc_disable_warnings,
        solc_arguments,
        solc_remaps=solc_remaps,
        working_dir=solc_working_dir,
        force_legacy_json=force_legacy_json,
    )


def solc_handle_contracts(
    targets_json: Dict,
    skip_filename: bool,
    compilation_unit: "CompilationUnit",
    target: str,
    solc_working_dir: Optional[str],
) -> None:
    """Populate the compilation unit from the compilation json artifacts

    Args:
        targets_json (Dict): Compilation artifacts
        skip_filename (bool): If true, skip the filename (for solc <0.4.10)
        compilation_unit (CompilationUnit): Associated compilation unit
        target (str): Path to the target
        solc_working_dir (Optional[str]): Working directory for running solc
    """
    is_above_0_8 = _is_at_or_above_minor_version(compilation_unit, 8)

    if "contracts" in targets_json:

        for original_contract_name, info in targets_json["contracts"].items():
            contract_name = extract_name(original_contract_name)
            # for solc < 0.4.10 we cant retrieve the filename from the ast
            if skip_filename:
                filename = convert_filename(
                    target,
                    relative_to_short,
                    compilation_unit.crytic_compile,
                    working_dir=solc_working_dir,
                )
            else:
                filename = convert_filename(
                    extract_filename(original_contract_name),
                    relative_to_short,
                    compilation_unit.crytic_compile,
                    working_dir=solc_working_dir,
                )

            source_unit = compilation_unit.create_source_unit(filename)

            source_unit.add_contract_name(contract_name)
            compilation_unit.filename_to_contracts[filename].add(contract_name)
            source_unit.abis[contract_name] = (
                json.loads(info["abi"]) if not is_above_0_8 else info["abi"]
            )
            source_unit.bytecodes_init[contract_name] = info["bin"]
            source_unit.bytecodes_runtime[contract_name] = info["bin-runtime"]
            source_unit.srcmaps_init[contract_name] = info["srcmap"].split(";")
            source_unit.srcmaps_runtime[contract_name] = info["srcmap-runtime"].split(";")
            userdoc = json.loads(info.get("userdoc", "{}")) if not is_above_0_8 else info["userdoc"]
            devdoc = json.loads(info.get("devdoc", "{}")) if not is_above_0_8 else info["devdoc"]
            natspec = Natspec(userdoc, devdoc)
            source_unit.natspec[contract_name] = natspec


def _is_at_or_above_minor_version(compilation_unit: "CompilationUnit", version: int) -> bool:
    """Checks if the solc version is at or above(=newer) a given minor (0.x.0) version

    Args:
        compilation_unit (CompilationUnit): Associated compilation unit
        version (int): version to check

    Returns:
        bool: True if the compilation unit version is above or equal to the provided version
    """
    assert compilation_unit.compiler_version.version
    return int(compilation_unit.compiler_version.version.split(".")[1]) >= version


def get_version(solc: str, env: Optional[Dict[str, str]]) -> str:
    """Obtains the version of the solc executable specified.

    Args:
        solc (str): The solc executable name to invoke.
        env (Optional[Dict[str, str]]): An optional environment key-value store which can be used when invoking the solc executable.

    Raises:
        InvalidCompilation: If solc failed to run

    Returns:
        str: Returns the version of the provided solc executable.
    """

    cmd = [solc, "--version"]
    LOGGER.info(
        "'%s' running",
        " ".join(cmd),
    )
    try:
        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            executable=shutil.which(cmd[0]),
        ) as process:
            stdout_bytes, stderr_bytes = process.communicate()
            stdout, stderr = (
                stdout_bytes.decode(errors="backslashreplace"),
                stderr_bytes.decode(errors="backslashreplace"),
            )  # convert bytestrings to unicode strings
            version = re.findall(r"\d+\.\d+\.\d+", stdout)
            if len(version) == 0:
                raise InvalidCompilation(
                    f"\nSolidity version not found:\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}"
                )
            return version[0]
    except OSError as error:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(error)


def is_optimized(solc_arguments: Optional[str]) -> bool:
    """Check if optimization are used

    Args:
        solc_arguments (Optional[str]): Solc arguments to check

    Returns:
        bool: True if the optimization are enabled
    """
    if solc_arguments:
        return "--optimize" in solc_arguments
    return False


def _build_options(compiler_version: CompilerVersion, force_legacy_json: bool) -> str:
    """
    Build the solc command line options

    Args:
        compiler_version (CompilerVersion): compiler version
        force_legacy_json (bool): true if the legacy json must be used

    Returns:
        str: options to be passed to the CI
    """
    old_04_versions = [f"0.4.{x}" for x in range(0, 12)]
    # compact-format was introduced in 0.4.12 and made the default in solc 0.8.10
    explicit_compact_format = (
        [f"0.4.{x}" for x in range(12, 27)]
        + [f"0.5.{x}" for x in range(0, 18)]
        + [f"0.6.{x}" for x in range(0, 13)]
        + [f"0.7.{x}" for x in range(0, 7)]
        + [f"0.8.{x}" for x in range(0, 10)]
    )
    assert compiler_version.version
    if compiler_version.version in old_04_versions or compiler_version.version.startswith("0.3"):
        return "abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc"
    if force_legacy_json:
        return "abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes"
    if compiler_version.version in explicit_compact_format:
        return "abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes,compact-format"

    return "abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes"


# pylint: disable=too-many-arguments,too-many-locals,too-many-branches,too-many-statements
def _run_solc(
    compilation_unit: "CompilationUnit",
    filename: str,
    solc: str,
    solc_disable_warnings: bool,
    solc_arguments: Optional[str],
    solc_remaps: Optional[Union[str, List[str]]] = None,
    env: Optional[Dict] = None,
    working_dir: Optional[Union[Path, str]] = None,
    force_legacy_json: bool = False,
) -> Dict:
    """Run solc.
    Ensure that crytic_compile.compiler_version is set prior calling _run_solc

    Args:
        compilation_unit (CompilationUnit): Associated compilation unit
        filename (str): Solidity file to compile
        solc (str): Solc binary
        solc_disable_warnings (bool): If True, disable solc warnings
        solc_arguments (Optional[str]): Additional solc cli arguments
        solc_remaps (Optional[Union[str, List[str]]], optional): Solc remaps. Can be a string where remap are separated with space, or list of str, or a list of. Defaults to None.
        env (Optional[Dict]): Environement variable when solc is run. Defaults to None.
        working_dir (Optional[Union[Path, str]]): Working directory when solc is run. Defaults to None.
        force_legacy_json (bool): Force to use the legacy json format. Defaults to False.

    Raises:
        InvalidCompilation: If solc failed to run or file is not a solidity file

    Returns:
        Dict: Json compilation artifacts
    """
    if not os.path.isfile(filename) and (
        not working_dir or not os.path.isfile(os.path.join(str(working_dir), filename))
    ):
        if os.path.isdir(filename):
            raise InvalidCompilation(
                f"{filename} is a directory. Expected a Solidity file when not using a compilation framework."
            )

        raise InvalidCompilation(
            f"{filename} does not exist. Are you in the correct working directory?"
        )

    if not filename.endswith(".sol"):
        raise InvalidCompilation(f"{filename} is not the expected format '.sol'")

    compilation_unit.compiler_version = CompilerVersion(
        compiler="solc", version=get_version(solc, env), optimized=is_optimized(solc_arguments)
    )

    compiler_version = compilation_unit.compiler_version
    assert compiler_version
    options = _build_options(compiler_version, force_legacy_json)

    cmd = [solc]
    if solc_remaps:
        if isinstance(solc_remaps, str):
            solc_remaps = solc_remaps.split(" ")
        cmd += solc_remaps
    cmd += [filename, "--combined-json", options]
    if solc_arguments:
        # To parse, we first split the string on each '--'
        solc_args = solc_arguments.split("--")
        # Split each argument on the first space found
        # One solc option may have multiple argument sepparated with ' '
        # For example: --allow-paths /tmp .
        # split() removes the delimiter, so we add it again
        solc_args_ = [("--" + x).split(" ", 1) for x in solc_args if x]
        # Flat the list of list
        solc_args = [item.strip() for sublist in solc_args_ for item in sublist if item]
        cmd += solc_args

    additional_kwargs: Dict = {"cwd": working_dir} if working_dir else {}
    if not compiler_version.version in [f"0.4.{x}" for x in range(0, 11)]:
        # Add --allow-paths argument, if it isn't already specified
        # We allow the CWD as well as the directory that contains the file
        if "--allow-paths" not in cmd:
            file_dir_start = os.path.normpath(os.path.dirname(filename))
            # Paths in the --allow-paths arg can't contain commas, since this is the delimeter
            # Try using absolute path; if it contains a comma, try using relative path instead
            file_dir = os.path.abspath(file_dir_start)
            if "," in file_dir:
                try:
                    file_dir = os.path.relpath(file_dir_start)
                except ValueError:
                    # relpath can fail if, for example, we're on Windows and the directory is on a different drive than CWD
                    pass

            # Even the relative path might have a comma in it, so we want to make sure first
            if "," not in file_dir:
                cmd += ["--allow-paths", ".," + file_dir]
            else:
                LOGGER.warning(
                    "Solc filepath contains a comma; omitting the --allow-paths argument. This may result in failed imports.\n"
                )

    try:
        LOGGER.info(
            "'%s' running",
            " ".join(cmd),
        )
        # pylint: disable=consider-using-with
        if env:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                executable=shutil.which(cmd[0]),
                env=env,
                **additional_kwargs,
            )
        else:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                executable=shutil.which(cmd[0]),
                **additional_kwargs,
            )
    except OSError as error:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(error)
    stdout_, stderr_ = process.communicate()
    stdout, stderr = (
        stdout_.decode(encoding="utf-8", errors="ignore"),
        stderr_.decode(encoding="utf-8", errors="ignore"),
    )  # convert bytestrings to unicode strings

    if stderr and (not solc_disable_warnings):
        LOGGER.info("Compilation warnings/errors on %s:\n%s", filename, stderr)

    try:
        ret: Dict = json.loads(stdout)
        return ret
    except json.decoder.JSONDecodeError:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(f"Invalid solc compilation {stderr}")


# pylint: disable=too-many-arguments
def _run_solcs_path(
    compilation_unit: "CompilationUnit",
    filename: str,
    solcs_path: Optional[Union[Dict, List[str]]],
    solc_disable_warnings: bool,
    solc_arguments: str,
    solc_remaps: Optional[Union[str, List[str]]] = None,
    env: Optional[Dict] = None,
    working_dir: Optional[str] = None,
    force_legacy_json: bool = False,
) -> Dict:
    """[summary]

    Args:
        compilation_unit (CompilationUnit): Associated compilation unit
        filename (str): Solidity file to compile
        solcs_path (Optional[Union[Dict, List[str]]]): List of solc binaries to try. If its a dict, in the form "version:path".
        solc_disable_warnings (bool): If True, disable solc warnings
        solc_arguments (str): Additional solc cli arguments
        solc_remaps (Optional[Union[str, List[str]]], optional): Solc remaps. Can be a string where remap are separated with space, or list of str, or a list of. Defaults to None.
        env (Optional[Dict]): Environement variable when solc is run. Defaults to None.
        working_dir (Optional[Union[Path, str]], optional): Working directory when solc is run. Defaults to None.
        force_legacy_json (bool): Force to use the legacy json format. Defaults to False.

    Raises:
        InvalidCompilation: [description]

    Returns:
        Dict: Json compilation artifacts
    """
    targets_json = None
    if isinstance(solcs_path, dict):
        guessed_solcs = _guess_solc(filename, working_dir)
        compilation_errors = []
        for guessed_solc in guessed_solcs:
            if not guessed_solc in solcs_path:
                continue
            try:
                targets_json = _run_solc(
                    compilation_unit,
                    filename,
                    solcs_path[guessed_solc],
                    solc_disable_warnings,
                    solc_arguments,
                    solc_remaps=solc_remaps,
                    env=env,
                    working_dir=working_dir,
                    force_legacy_json=force_legacy_json,
                )
                break
            except InvalidCompilation:
                pass

    if not targets_json:
        if isinstance(solcs_path, dict):
            solc_bins: List[str] = list(solcs_path.values())
        elif solcs_path:
            solc_bins = solcs_path
        else:
            solc_bins = []

        for solc_bin in solc_bins:
            try:
                targets_json = _run_solc(
                    compilation_unit,
                    filename,
                    solc_bin,
                    solc_disable_warnings,
                    solc_arguments,
                    solc_remaps=solc_remaps,
                    env=env,
                    working_dir=working_dir,
                    force_legacy_json=force_legacy_json,
                )
                break
            except InvalidCompilation as ic:
                compilation_errors.append(solc_bin + ": " + ic.args[0])

    if not targets_json:
        raise InvalidCompilation(
            "Invalid solc compilation, none of the solc versions provided worked:\n"
            + "\n".join(compilation_errors)
        )

    return targets_json


# pylint: disable=too-many-arguments
def _run_solcs_env(
    compilation_unit: "CompilationUnit",
    filename: str,
    solc: str,
    solc_disable_warnings: bool,
    solc_arguments: str,
    solc_remaps: Optional[Union[List[str], str]] = None,
    env: Optional[Dict] = None,
    working_dir: Optional[str] = None,
    solcs_env: Optional[List[str]] = None,
    force_legacy_json: bool = False,
) -> Dict:
    """Run different solc based on environment variable
    This is mostly a legacy function for old solc-select usages

    Args:
        compilation_unit (CompilationUnit): Associated compilation unit
        filename (str): Solidity file to compile
        solc (str): Solc binary
        solc_disable_warnings (bool): If True, disable solc warnings
        solc_arguments (str): Additional solc cli arguments
        solc_remaps (Optional[Union[str, List[str]]], optional): Solc remaps. Can be a string where remap are separated with space, or list of str, or a list of. Defaults to None.
        env (Optional[Dict], optional): Environement variable when solc is run. Defaults to None.
        working_dir (Optional[Union[Path, str]], optional): Working directory when solc is run. Defaults to None.
        solcs_env (Optional[List[str]]): List of solc env variable to try. Defaults to None.
        force_legacy_json (bool): Force to use the legacy json format. Defaults to False.

    Raises:
        InvalidCompilation: If solc failed

    Returns:
        Dict: Json compilation artifacts
    """
    env = dict(os.environ) if env is None else env
    targets_json = None
    guessed_solcs = _guess_solc(filename, working_dir)
    compilation_errors = []
    for guessed_solc in guessed_solcs:
        if solcs_env and not guessed_solc in solcs_env:
            continue
        try:
            env["SOLC_VERSION"] = guessed_solc
            targets_json = _run_solc(
                compilation_unit,
                filename,
                solc,
                solc_disable_warnings,
                solc_arguments,
                solc_remaps=solc_remaps,
                env=env,
                working_dir=working_dir,
                force_legacy_json=force_legacy_json,
            )
            break
        except InvalidCompilation:
            pass

    if not targets_json:
        solc_versions_env = solcs_env if solcs_env else []

        for version_env in solc_versions_env:
            try:
                env["SOLC_VERSION"] = version_env
                targets_json = _run_solc(
                    compilation_unit,
                    filename,
                    solc,
                    solc_disable_warnings,
                    solc_arguments,
                    solc_remaps=solc_remaps,
                    env=env,
                    working_dir=working_dir,
                    force_legacy_json=force_legacy_json,
                )
                break
            except InvalidCompilation as ic:
                compilation_errors.append(version_env + ": " + ic.args[0])

    if not targets_json:
        raise InvalidCompilation(
            "Invalid solc compilation, none of the solc versions provided worked:\n"
            + "\n".join(compilation_errors)
        )

    return targets_json


PATTERN = re.compile(r"pragma solidity\s*(?:\^|>=|<=)?\s*(\d+\.\d+\.\d+)")


def _guess_solc(target: str, solc_working_dir: Optional[str]) -> List[str]:
    """Guess the Solidity version (look for "pragma solidity")

    Args:
        target (str): Solidity filename
        solc_working_dir (Optional[str]): Working directory

    Returns:
        List[str]: List of potential solidity version
    """
    if solc_working_dir:
        target = os.path.join(solc_working_dir, target)
    with open(target, encoding="utf8") as file_desc:
        buf = file_desc.read()
        return PATTERN.findall(buf)


def relative_to_short(relative: Path) -> Path:
    """Convert relative to short (does nothing for direct solc)

    Args:
        relative (Path): target

    Returns:
        Path: Converted path
    """
    return relative
