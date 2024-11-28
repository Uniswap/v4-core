"""
Etherlime platform. https://github.com/LimeChain/etherlime
"""

import glob
import json
import logging
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, List, Optional, Any

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename

# Cycle dependency
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


def _run_etherlime(target: str, npx_disable: bool, compile_arguments: Optional[str]) -> None:
    """Run etherlime

    Args:
        target (str): path to the target
        npx_disable (bool): true if npx should not be used
        compile_arguments (Optional[str]): additional arguments

    Raises:
        InvalidCompilation: if etherlime fails
    """
    cmd = ["etherlime", "compile", target, "deleteCompiledFiles=true"]

    if not npx_disable:
        cmd = ["npx"] + cmd

    if compile_arguments:
        cmd += compile_arguments.split(" ")

    try:
        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=target,
            executable=shutil.which(cmd[0]),
        ) as process:
            stdout_bytes, stderr_bytes = process.communicate()
            stdout, stderr = (
                stdout_bytes.decode(errors="backslashreplace"),
                stderr_bytes.decode(errors="backslashreplace"),
            )  # convert bytestrings to unicode strings

            LOGGER.info(stdout)

            if stderr:
                LOGGER.error(stderr)
    except OSError as error:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(error)


class Etherlime(AbstractPlatform):
    """
    Etherlime platform
    """

    NAME = "Etherlime"
    PROJECT_URL = "https://github.com/LimeChain/etherlime"
    TYPE = Type.ETHERLIME

    # pylint: disable=too-many-locals
    def compile(self, crytic_compile: "CryticCompile", **kwargs: Any) -> None:
        """Run the compilation

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile object
            **kwargs: optional arguments. Used "etherlime_ignore_compile", "ignore_compile"

        Raises:
            InvalidCompilation: if etherlime failed to run
        """

        etherlime_ignore_compile = kwargs.get("etherlime_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )

        build_directory = "build"
        compile_arguments: Optional[str] = kwargs.get("etherlime_compile_arguments", None)
        npx_disable: bool = kwargs.get("npx_disable", False)

        if not etherlime_ignore_compile:
            _run_etherlime(self._target, npx_disable, compile_arguments)

        # similar to truffle
        if not os.path.isdir(os.path.join(self._target, build_directory)):
            raise InvalidCompilation(
                "No truffle build directory found, did you run `truffle compile`?"
            )
        filenames = glob.glob(os.path.join(self._target, build_directory, "*.json"))

        version = None
        compiler = "solc-js"

        compilation_unit = CompilationUnit(crytic_compile, str(self._target))

        for file in filenames:
            with open(file, encoding="utf8") as file_desc:
                target_loaded = json.load(file_desc)

                if version is None:
                    if "compiler" in target_loaded:
                        if "version" in target_loaded["compiler"]:
                            version = re.findall(
                                r"\d+\.\d+\.\d+", target_loaded["compiler"]["version"]
                            )[0]

                if "ast" not in target_loaded:
                    continue

                filename_txt = target_loaded["ast"]["absolutePath"]
                filename = convert_filename(filename_txt, _relative_to_short, crytic_compile)

                source_unit = compilation_unit.create_source_unit(filename)

                source_unit.ast = target_loaded["ast"]
                contract_name = target_loaded["contractName"]

                compilation_unit.filename_to_contracts[filename].add(contract_name)
                source_unit.add_contract_name(contract_name)
                source_unit.abis[contract_name] = target_loaded["abi"]
                source_unit.bytecodes_init[contract_name] = target_loaded["bytecode"].replace(
                    "0x", ""
                )
                source_unit.bytecodes_runtime[contract_name] = target_loaded[
                    "deployedBytecode"
                ].replace("0x", "")
                source_unit.srcmaps_init[contract_name] = target_loaded["sourceMap"].split(";")
                source_unit.srcmaps_runtime[contract_name] = target_loaded[
                    "deployedSourceMap"
                ].split(";")

                userdoc = target_loaded.get("userdoc", {})
                devdoc = target_loaded.get("devdoc", {})
                natspec = Natspec(userdoc, devdoc)
                source_unit.natspec[contract_name] = natspec

        compilation_unit.compiler_version = CompilerVersion(
            compiler=compiler, version=version, optimized=_is_optimized(compile_arguments)
        )

    def clean(self, **_kwargs: str) -> None:
        # TODO: research if there's a way to clean artifacts
        pass

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is an etherlime project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used "etherlime_ignore"

        Returns:
            bool: True if the target is a etherlime project
        """
        etherlime_ignore = kwargs.get("etherlime_ignore", False)
        if etherlime_ignore:
            return False
        if os.path.isfile(os.path.join(target, "package.json")):
            with open(os.path.join(target, "package.json"), encoding="utf8") as file_desc:
                package = json.load(file_desc)
            if "dependencies" in package:
                return (
                    "etherlime-lib" in package["dependencies"]
                    or "etherlime" in package["dependencies"]
                )
            if "devDependencies" in package:
                return (
                    "etherlime-lib" in package["devDependencies"]
                    or "etherlime" in package["devDependencies"]
                )
        return False

    def is_dependency(self, path: str) -> bool:
        """Check if the path is a dependency

        Args:
            path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        if path in self._cached_dependencies:
            return self._cached_dependencies[path]
        ret = "node_modules" in Path(path).parts
        self._cached_dependencies[path] = ret
        return ret

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return ["etherlime test"]


def _is_optimized(compile_arguments: Optional[str]) -> bool:
    """Check if the optimization is enabled

    Args:
        compile_arguments (Optional[str]): list of compilation arguments

    Returns:
        bool: True if the optimizations are enabled
    """
    if compile_arguments:
        return "--run" in compile_arguments
    return False


def _relative_to_short(relative: Path) -> Path:
    """Translate relative path to short

    Args:
        relative (Path): path to the target

    Returns:
        Path: Translated path
    """
    short = relative
    try:
        short = short.relative_to(Path("contracts"))
    except ValueError:
        try:
            short = short.relative_to("node_modules")
        except ValueError:
            pass
    return short
