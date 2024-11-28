"""
Vyper platform
"""
import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Optional

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename

# Handle cycle
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


class VyperStandardJson(AbstractPlatform):
    """
    Vyper platform
    """

    NAME = "vyper"
    PROJECT_URL = "https://github.com/vyperlang/vyper"
    TYPE = Type.VYPER

    def __init__(self, target: Optional[Path] = None, **_kwargs: str):
        super().__init__(str(target), **_kwargs)
        self.standard_json_input = {
            "language": "Vyper",
            "sources": {},
            "settings": {
                "outputSelection": {
                    "*": {
                        "*": [
                            "abi",
                            "devdoc",
                            "userdoc",
                            "evm.bytecode",
                            "evm.deployedBytecode",
                            "evm.deployedBytecode.sourceMap",
                        ],
                        "": ["ast"],
                    }
                }
            },
        }

    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Compile the target

        Args:
            crytic_compile (CryticCompile): CryticCompile object to populate
            **kwargs: optional arguments. Used "vyper"


        """
        target = self._target
        # If the target was a directory `add_source_file` should have been called
        # by `compile_all`. Otherwise, we should have a single file target.
        if self._target is not None and os.path.isfile(self._target):
            self.add_source_files([target])

        vyper_bin = kwargs.get("vyper", "vyper")

        compilation_artifacts = _run_vyper_standard_json(self.standard_json_input, vyper_bin)
        compilation_unit = CompilationUnit(crytic_compile, str(target))

        compiler_version = compilation_artifacts["compiler"].split("-")[1]
        if compiler_version != "0.3.7":
            LOGGER.info("Vyper != 0.3.7 support is a best effort and might fail")
        compilation_unit.compiler_version = CompilerVersion(
            compiler="vyper", version=compiler_version, optimized=False
        )

        for source_file, contract_info in compilation_artifacts["contracts"].items():
            filename = convert_filename(source_file, _relative_to_short, crytic_compile)
            source_unit = compilation_unit.create_source_unit(filename)
            for contract_name, contract_metadata in contract_info.items():
                source_unit.add_contract_name(contract_name)
                compilation_unit.filename_to_contracts[filename].add(contract_name)

                source_unit.abis[contract_name] = contract_metadata["abi"]
                source_unit.bytecodes_init[contract_name] = contract_metadata["evm"]["bytecode"][
                    "object"
                ].replace("0x", "")
                # Vyper does not provide the source mapping for the init bytecode
                source_unit.srcmaps_init[contract_name] = []
                source_unit.srcmaps_runtime[contract_name] = contract_metadata["evm"][
                    "deployedBytecode"
                ]["sourceMap"].split(";")
                source_unit.bytecodes_runtime[contract_name] = contract_metadata["evm"][
                    "deployedBytecode"
                ]["object"].replace("0x", "")
                source_unit.natspec[contract_name] = Natspec(
                    contract_metadata["userdoc"], contract_metadata["devdoc"]
                )

        for source_file, ast in compilation_artifacts["sources"].items():
            filename = convert_filename(source_file, _relative_to_short, crytic_compile)
            source_unit = compilation_unit.create_source_unit(filename)
            source_unit.ast = ast

    def add_source_files(self, file_paths: List[str]) -> None:
        """
        Append files

        Args:
            file_paths (List[str]): files to append

        Returns:

        """

        for file_path in file_paths:
            with open(file_path, "r", encoding="utf8") as f:
                self.standard_json_input["sources"][file_path] = {  # type: ignore
                    "content": f.read(),
                }

    def clean(self, **_kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **_kwargs: unused.
        """
        return

    def is_dependency(self, _path: str) -> bool:
        """Check if the path is a dependency (not supported for vyper)

        Args:
            _path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        return False

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a vyper project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used "vyper_ignore"

        Returns:
            bool: True if the target is a vyper project
        """
        vyper_ignore = kwargs.get("vyper_ignore", False)
        if vyper_ignore:
            return False
        return os.path.isfile(target) and target.endswith(".vy")

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return []


def _run_vyper_standard_json(
    standard_json_input: Dict, vyper: str, env: Optional[Dict] = None
) -> Dict:
    """Run vyper and write compilation output to a file

    Args:
        standard_json_input (Dict): Dict containing the vyper standard json input
        vyper (str): vyper binary
        env (Optional[Dict], optional): Environment variables. Defaults to None.

    Raises:
        InvalidCompilation: If vyper failed to run

    Returns:
        Dict: Vyper json compilation artifact
    """
    cmd = [vyper, "--standard-json"]

    with subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        executable=shutil.which(cmd[0]),
    ) as process:

        stdout_b, stderr_b = process.communicate(json.dumps(standard_json_input).encode("utf-8"))
        stdout, _stderr = (
            stdout_b.decode(),
            stderr_b.decode(errors="backslashreplace"),
        )  # convert bytestrings to unicode strings

        vyper_standard_output = json.loads(stdout)

        if "errors" in vyper_standard_output:

            has_errors = False
            for diagnostic in vyper_standard_output["errors"]:

                if diagnostic["severity"] == "warning":
                    continue

                msg = diagnostic.get("formattedMessage", diagnostic["message"])
                LOGGER.error(msg)
                has_errors = True

            if has_errors:
                raise InvalidCompilation("Vyper compilation errored")

        return vyper_standard_output


def _relative_to_short(relative: Path) -> Path:
    """Translate relative path to short (do nothing for vyper)

    Args:
        relative (Path): path to the target

    Returns:
        Path: Translated path
    """
    return relative
