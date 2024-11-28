"""
Dapp platform. https://github.com/dapphub/dapptools
"""

import glob
import json
import logging
import os
import re
import shutil
import subprocess
from pathlib import Path

# Cycle dependency
from typing import TYPE_CHECKING, List, Optional

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename, extract_name

# Handle cycle
from crytic_compile.utils.natspec import Natspec
from crytic_compile.utils.subprocess import run

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


class Dapp(AbstractPlatform):
    """
    Dapp class
    """

    NAME = "Dapp"
    PROJECT_URL = "https://github.com/dapphub/dapptools"
    TYPE = Type.DAPP

    # pylint: disable=too-many-locals
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Run the compilation

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile object
            **kwargs: optional arguments. Used: "dapp_ignore_compile", "ignore_compile"
        """

        dapp_ignore_compile = kwargs.get("dapp_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )
        directory = os.path.join(self._target, "out")

        if not dapp_ignore_compile:
            _run_dapp(self._target)

        compilation_unit = CompilationUnit(crytic_compile, str(self._target))

        compilation_unit.compiler_version = _get_version(self._target)

        optimized = False

        with open(os.path.join(directory, "dapp.sol.json"), "r", encoding="utf8") as file_desc:
            targets_json = json.load(file_desc)

            version: Optional[str] = None
            if "version" in targets_json:
                version = re.findall(r"\d+\.\d+\.\d+", targets_json["version"])[0]

            for path, info in targets_json["sources"].items():
                path = convert_filename(
                    path, _relative_to_short, crytic_compile, working_dir=self._target
                )
                source_unit = compilation_unit.create_source_unit(path)
                source_unit.ast = info["ast"]

            for original_filename, contracts_info in targets_json["contracts"].items():

                filename = convert_filename(
                    original_filename, lambda x: x, crytic_compile, self._target
                )

                source_unit = compilation_unit.create_source_unit(filename)

                for original_contract_name, info in contracts_info.items():
                    if "metadata" in info:
                        metadata = json.loads(info["metadata"])
                        if (
                            "settings" in metadata
                            and "optimizer" in metadata["settings"]
                            and "enabled" in metadata["settings"]["optimizer"]
                        ):
                            optimized |= metadata["settings"]["optimizer"]["enabled"]
                    contract_name = extract_name(original_contract_name)
                    source_unit.add_contract_name(contract_name)
                    compilation_unit.filename_to_contracts[filename].add(contract_name)

                    source_unit.abis[contract_name] = info["abi"]
                    source_unit.bytecodes_init[contract_name] = info["evm"]["bytecode"]["object"]
                    source_unit.bytecodes_runtime[contract_name] = info["evm"]["deployedBytecode"][
                        "object"
                    ]
                    source_unit.srcmaps_init[contract_name] = info["evm"]["bytecode"][
                        "sourceMap"
                    ].split(";")
                    source_unit.srcmaps_runtime[contract_name] = info["evm"]["bytecode"][
                        "sourceMap"
                    ].split(";")
                    userdoc = info.get("userdoc", {})
                    devdoc = info.get("devdoc", {})
                    natspec = Natspec(userdoc, devdoc)
                    source_unit.natspec[contract_name] = natspec

                    if version is None:
                        metadata = json.loads(info["metadata"])
                        version = re.findall(r"\d+\.\d+\.\d+", metadata["compiler"]["version"])[0]

        compilation_unit.compiler_version = CompilerVersion(
            compiler="solc", version=version, optimized=optimized
        )

    def clean(self, **kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **kwargs: optional arguments.
        """

        dapp_ignore_compile = kwargs.get("dapp_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )
        if dapp_ignore_compile:
            return

        run(["dapp", "clean"], cwd=self._target)

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a dapp project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used: "dapp_ignore"

        Returns:
            bool: True if the target is a dapp project
        """
        dapp_ignore = kwargs.get("dapp_ignore", False)
        if dapp_ignore:
            return False
        makefile = os.path.join(target, "Makefile")
        if os.path.isfile(makefile):
            with open(makefile, encoding="utf8") as file_desc:
                txt = file_desc.read()
                return "dapp " in txt
        return False

    def is_dependency(self, path: str) -> bool:
        """Check if the path is a dependency (not supported for brownie)

        Args:
            path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        if path in self._cached_dependencies:
            return self._cached_dependencies[path]
        ret = "node_modules" in Path(path).parts
        self._cached_dependencies[path] = ret
        return "lib" in Path(path).parts

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return ["dapp test"]


def _run_dapp(target: str) -> None:
    """Run the dapp compilation

    Args:
        target (str): path to the target

    Raises:
        InvalidCompilation: If dapp failed to run
    """
    # pylint: disable=import-outside-toplevel
    from crytic_compile.platform.exceptions import InvalidCompilation

    cmd = ["dapp", "build"]

    try:
        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=target,
            executable=shutil.which(cmd[0]),
        ) as process:
            _, _ = process.communicate()
    except OSError as error:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(error)


def _get_version(target: str) -> CompilerVersion:
    """Get the compiler version

    Args:
        target (str): path to the target

    Returns:
        CompilerVersion: compiler information
    """
    files = glob.glob(target + "/**/*meta.json", recursive=True)
    version: Optional[str] = None
    optimized = None
    compiler = "solc"
    for file in files:
        if version is None:
            with open(file, encoding="utf8") as file_desc:
                config = json.load(file_desc)
            if "compiler" in config:
                if "version" in config["compiler"]:
                    versions = re.findall(r"\d+\.\d+\.\d+", config["compiler"]["version"])
                    if versions:
                        version = versions[0]
            if "settings" in config:
                if "optimizer" in config["settings"]:
                    if "enabled" in config["settings"]["optimizer"]:
                        optimized = config["settings"]["optimizer"]["enabled"]

    return CompilerVersion(compiler=compiler, version=version, optimized=optimized)


def _relative_to_short(relative: Path) -> Path:
    """Translate relative path to short (do nothing for brownie)

    Args:
        relative (Path): path to the target

    Returns:
        Path: Translated path
    """
    short = relative
    try:
        short = short.relative_to(Path("src"))
    except ValueError:
        try:
            short = short.relative_to("lib")
        except ValueError:
            pass
    return short
