"""
Embark platform. https://github.com/embark-framework/embark
"""

import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, List

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename, extract_filename, extract_name

# Cycle dependency
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


class Embark(AbstractPlatform):
    """
    Embark platform
    """

    NAME = "Embark"
    PROJECT_URL = "https://github.com/embarklabs/embark"
    TYPE = Type.EMBARK

    # pylint:disable=too-many-branches,too-many-statements,too-many-locals
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Run the compilation

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile object
            **kwargs: optional arguments. Used: "embark_ignore_compile", "ignore_compile", "embark_overwrite_config"

        Raises:
            InvalidCompilation: if embark failed to run
        """
        embark_ignore_compile = kwargs.get("embark_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )
        embark_overwrite_config = kwargs.get("embark_overwrite_config", False)

        plugin_name = "@trailofbits/embark-contract-info"
        with open(os.path.join(self._target, "embark.json"), encoding="utf8") as file_desc:
            embark_json = json.load(file_desc)
        if embark_overwrite_config:
            write_embark_json = False
            if not "plugins" in embark_json:
                embark_json["plugins"] = {plugin_name: {"flags": ""}}
                write_embark_json = True
            elif not plugin_name in embark_json["plugins"]:
                embark_json["plugins"][plugin_name] = {"flags": ""}
                write_embark_json = True
            if write_embark_json:
                try:
                    with subprocess.Popen(
                        ["npm", "install", plugin_name],
                        cwd=self._target,
                        executable=shutil.which("npm"),
                    ) as process:
                        _, stderr = process.communicate()
                        with open(
                            os.path.join(self._target, "embark.json"), "w", encoding="utf8"
                        ) as outfile:
                            json.dump(embark_json, outfile, indent=2)
                except OSError as error:
                    # pylint: disable=raise-missing-from
                    raise InvalidCompilation(error)

        else:
            if (not "plugins" in embark_json) or (not plugin_name in embark_json["plugins"]):
                raise InvalidCompilation(
                    "embark-contract-info plugin was found in embark.json. "
                    "Please install the plugin (see "
                    "https://github.com/crytic/crytic-compile/wiki/Usage#embark)"
                    ", or use --embark-overwrite-config."
                )

        if not embark_ignore_compile:
            try:
                cmd = ["embark", "build", "--contracts"]
                if not kwargs.get("npx_disable", False):
                    cmd = ["npx"] + cmd
                # pylint: disable=consider-using-with
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    cwd=self._target,
                    executable=shutil.which(cmd[0]),
                )
            except OSError as error:
                # pylint: disable=raise-missing-from
                raise InvalidCompilation(error)
            stdout, stderr = process.communicate()
            LOGGER.info("%s\n", stdout.decode(errors="backslashreplace"))
            if stderr:
                # Embark might return information to stderr, but compile without issue
                LOGGER.error("%s", stderr.decode(errors="backslashreplace"))
        infile = os.path.join(self._target, "crytic-export", "contracts-embark.json")
        if not os.path.isfile(infile):
            raise InvalidCompilation(
                "Embark did not generate the AST file. Is Embark installed "
                "(npm install -g embark)? Is embark-contract-info installed? (npm install -g embark)."
            )
        compilation_unit = CompilationUnit(crytic_compile, str(self._target))

        compilation_unit.compiler_version = _get_version(self._target)

        with open(infile, "r", encoding="utf8") as file_desc:
            targets_loaded = json.load(file_desc)

            if "sources" in targets_loaded:
                compilation_unit.filenames = [
                    convert_filename(
                        path, _relative_to_short, crytic_compile, working_dir=self._target
                    )
                    for path in targets_loaded["sources"]
                ]

            for k, ast in targets_loaded["asts"].items():
                filename = convert_filename(
                    k, _relative_to_short, crytic_compile, working_dir=self._target
                )
                source_unit = compilation_unit.create_source_unit(filename)
                source_unit.ast = ast

            if not "contracts" in targets_loaded:
                LOGGER.error(
                    "Incorrect json file generated. Are you using %s >= 1.1.0?", plugin_name
                )
                raise InvalidCompilation(
                    f"Incorrect json file generated. Are you using {plugin_name} >= 1.1.0?"
                )

            for original_contract_name, info in targets_loaded["contracts"].items():
                contract_name = extract_name(original_contract_name)
                filename = convert_filename(
                    extract_filename(original_contract_name),
                    _relative_to_short,
                    crytic_compile,
                    working_dir=self._target,
                )

                source_unit = compilation_unit.create_source_unit(filename)

                compilation_unit.filename_to_contracts[filename].add(contract_name)
                source_unit.add_contract_name(contract_name)

                if "abi" in info:
                    source_unit.abis[contract_name] = info["abi"]
                if "bin" in info:
                    source_unit.bytecodes_init[contract_name] = info["bin"].replace("0x", "")
                if "bin-runtime" in info:
                    source_unit.bytecodes_runtime[contract_name] = info["bin-runtime"].replace(
                        "0x", ""
                    )
                if "srcmap" in info:
                    source_unit.srcmaps_init[contract_name] = info["srcmap"].split(";")
                if "srcmap-runtime" in info:
                    source_unit.srcmaps_runtime[contract_name] = info["srcmap-runtime"].split(";")

                userdoc = info.get("userdoc", {})
                devdoc = info.get("devdoc", {})
                natspec = Natspec(userdoc, devdoc)
                source_unit.natspec[contract_name] = natspec

    def clean(self, **_kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **_kwargs: unused.
        """
        return

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is an embark project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used: "embark_ignore"

        Returns:
            bool: True if the target is an embark project
        """
        embark_ignore = kwargs.get("embark_ignore", False)
        if embark_ignore:
            return False
        return os.path.isfile(os.path.join(target, "embark.json"))

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
        return ["embark test"]


def _get_version(target: str) -> CompilerVersion:
    """Get the compiler information

    Args:
        target (str): path to the target

    Returns:
        CompilerVersion: Compiler information
    """
    with open(os.path.join(target, "embark.json"), encoding="utf8") as file_desc:
        config = json.load(file_desc)
        version = "0.5.0"  # default version with Embark 0.4
        if "versions" in config:
            if "solc" in config["versions"]:
                version = config["versions"]["solc"]
        optimized = False
        if "options" in config:
            if "solc" in config["options"]:
                if "optimize" in config["options"]["solc"]:
                    optimized = config["options"]["solc"]

    return CompilerVersion(compiler="solc-js", version=version, optimized=optimized)


def _relative_to_short(relative: Path) -> Path:
    """Translate relative path to short

    Args:
        relative (Path): path to the target

    Returns:
        Path: Translated path
    """
    short = relative
    try:
        short = short.relative_to(Path(".embark", "contracts"))
    except ValueError:
        try:
            short = short.relative_to("node_modules")
        except ValueError:
            pass
    return short
