"""
Waffle platform
"""

import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Optional

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform.abstract_platform import AbstractPlatform, PlatformConfig
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename

# Handle cycle
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


class Waffle(AbstractPlatform):
    """
    Waffle platform
    """

    NAME = "Waffle"
    PROJECT_URL = "https://github.com/EthWorks/Waffle"
    TYPE = Type.WAFFLE

    # pylint: disable=too-many-locals,too-many-branches,too-many-statements
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Compile the project and populate the CryticCompile object

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile
            **kwargs: optional arguments. Used "waffle_ignore_compile", "ignore_compile", "npx_disable",
                "waffle_config_file"

        Raises:
            InvalidCompilation: If the waffle failed to run
        """

        waffle_ignore_compile = kwargs.get("waffle_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )
        target = self._target

        cmd = ["waffle"]
        if not kwargs.get("npx_disable", False):
            cmd = ["npx"] + cmd

        # Default behaviour (without any config_file)
        build_directory = os.path.join("build")
        compiler = "native"
        config: Dict = {}

        config_file = kwargs.get("waffle_config_file", "waffle.json")

        potential_config_files = list(Path(target).rglob("*waffle*.json"))
        if potential_config_files and len(potential_config_files) == 1:
            config_file = str(potential_config_files[0])

        # Read config file
        if config_file:
            config = _load_config(config_file)

            # old version
            if "compiler" in config:
                compiler = config["compiler"]
            if "compilerType" in config:
                compiler = config["compilerType"]

            if "compilerVersion" in config:
                version = config["compilerVersion"]
            else:
                version = _get_version(compiler, target, config=config)

            if "targetPath" in config:
                build_directory = config["targetPath"]

        else:
            version = _get_version(compiler, target)

        if "outputType" not in config or config["outputType"] != "all":
            config["outputType"] = "all"

        needed_config = {
            "compilerOptions": {
                "outputSelection": {
                    "*": {
                        "*": [
                            "evm.bytecode.object",
                            "evm.deployedBytecode.object",
                            "abi",
                            "evm.bytecode.sourceMap",
                            "evm.deployedBytecode.sourceMap",
                        ],
                        "": ["ast"],
                    }
                }
            }
        }

        # Set the config as it should be
        if "compilerOptions" in config:
            curr_config: Dict = config["compilerOptions"]
            curr_needed_config: Dict = needed_config["compilerOptions"]
            if "outputSelection" in curr_config:
                curr_config = curr_config["outputSelection"]
                curr_needed_config = curr_needed_config["outputSelection"]
                if "*" in curr_config:
                    curr_config = curr_config["*"]
                    curr_needed_config = curr_needed_config["*"]
                    if "*" in curr_config:
                        curr_config["*"] += curr_needed_config["*"]
                    else:
                        curr_config["*"] = curr_needed_config["*"]

                    if "" in curr_config:
                        curr_config[""] += curr_needed_config[""]
                    else:
                        curr_config[""] = curr_needed_config[""]

                else:
                    curr_config["*"] = curr_needed_config["*"]

            else:
                curr_config["outputSelection"] = curr_needed_config["outputSelection"]
        else:
            config["compilerOptions"] = needed_config["compilerOptions"]

        if not waffle_ignore_compile:
            with tempfile.NamedTemporaryFile(mode="w", suffix=".json", dir=target) as file_desc:
                json.dump(config, file_desc)
                file_desc.flush()

                # cmd += [os.path.relpath(file_desc.name)]
                cmd += [Path(file_desc.name).name]

                LOGGER.info("Temporary file created: %s", file_desc.name)
                LOGGER.info("'%s running", " ".join(cmd))

                try:
                    with subprocess.Popen(
                        cmd,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        cwd=target,
                        executable=shutil.which(cmd[0]),
                    ) as process:
                        stdout, stderr = process.communicate()
                        if stdout:
                            LOGGER.info(stdout.decode(errors="backslashreplace"))
                        if stderr:
                            LOGGER.error(stderr.decode(errors="backslashreplace"))
                except OSError as error:
                    # pylint: disable=raise-missing-from
                    raise InvalidCompilation(error)

        if not os.path.isdir(os.path.join(target, build_directory)):
            raise InvalidCompilation("`waffle` compilation failed: build directory not found")

        combined_path = os.path.join(target, build_directory, "Combined-Json.json")
        if not os.path.exists(combined_path):
            raise InvalidCompilation("`Combined-Json.json` not found")

        with open(combined_path, encoding="utf8") as f:
            target_all = json.load(f)

        optimized = None

        compilation_unit = CompilationUnit(crytic_compile, str(target))

        if "sources" in target_all:
            compilation_unit.filenames = [
                convert_filename(path, _relative_to_short, crytic_compile, working_dir=target)
                for path in target_all["sources"]
            ]

        for contract in target_all["contracts"]:
            target_loaded = target_all["contracts"][contract]
            contract = contract.split(":")
            filename = convert_filename(
                contract[0], _relative_to_short, crytic_compile, working_dir=target
            )

            contract_name = contract[1]
            source_unit = compilation_unit.create_source_unit(filename)

            source_unit.ast = target_all["sources"][contract[0]]["AST"]
            compilation_unit.filename_to_contracts[filename].add(contract_name)
            source_unit.add_contract_name(contract_name)
            source_unit.abis[contract_name] = target_loaded["abi"]

            userdoc = target_loaded.get("userdoc", {})
            devdoc = target_loaded.get("devdoc", {})
            natspec = Natspec(userdoc, devdoc)
            source_unit.natspec[contract_name] = natspec

            source_unit.bytecodes_init[contract_name] = target_loaded["evm"]["bytecode"]["object"]
            source_unit.srcmaps_init[contract_name] = target_loaded["evm"]["bytecode"][
                "sourceMap"
            ].split(";")
            source_unit.bytecodes_runtime[contract_name] = target_loaded["evm"]["deployedBytecode"][
                "object"
            ]
            source_unit.srcmaps_runtime[contract_name] = target_loaded["evm"]["deployedBytecode"][
                "sourceMap"
            ].split(";")

        compilation_unit.compiler_version = CompilerVersion(
            compiler=compiler, version=version, optimized=optimized
        )

    def clean(self, **_kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **_kwargs: unused.
        """
        return

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a waffle project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used "waffle_ignore"

        Returns:
            bool: True if the target is a waffle project
        """
        waffle_ignore = kwargs.get("waffle_ignore", False)
        if waffle_ignore:
            return False

        if os.path.isfile(os.path.join(target, "waffle.json")) or os.path.isfile(
            os.path.join(target, ".waffle.json")
        ):
            return True

        if os.path.isfile(os.path.join(target, "package.json")):
            with open(os.path.join(target, "package.json"), encoding="utf8") as file_desc:
                package = json.load(file_desc)
            if "dependencies" in package:
                return "ethereum-waffle" in package["dependencies"]
            if "devDependencies" in package:
                return "ethereum-waffle" in package["devDependencies"]

        return False

    @staticmethod
    def config(working_dir: str) -> Optional[PlatformConfig]:
        """Return configuration data that should be passed to solc, such as remappings.

        Args:
            working_dir (str): path to the working directory

        Returns:
            Optional[PlatformConfig]: Platform configuration data such as optimization, remappings...
        """
        return None

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
        return ["npx mocha"]


def _load_config(config_file: str) -> Dict:
    """Load the config file

    Args:
        config_file (str): config file to load

    Raises:
        InvalidCompilation: If the config file lacks "module.export"

    Returns:
        Dict: [description]
    """
    with open(
        config_file,
        "r",
        encoding="utf8",
    ) as file_desc:
        content = file_desc.read()

    if "module.exports" in content:
        raise InvalidCompilation("module.export is required for waffle")
    return json.loads(content)


def _get_version(compiler: str, cwd: str, config: Optional[Dict] = None) -> str:
    """Return the solidity verison used

    Args:
        compiler (str): compiler used
        cwd (str): Working directory
        config (Optional[Dict], optional): Config as a json. Defaults to None.

    Raises:
        InvalidCompilation: If the solidity version was not found

    Returns:
        str: Solidity version used
    """
    version = ""
    if config is not None and "solcVersion" in config:
        version = re.findall(r"\d+\.\d+\.\d+", config["solcVersion"])[0]

    elif config is not None and compiler == "dockerized-solc":
        version = config["docker-tag"]

    elif compiler == "native":
        cmd = ["solc", "--version"]
        try:
            with subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=cwd,
                executable=shutil.which(cmd[0]),
            ) as process:
                stdout_bytes, _ = process.communicate()
                stdout_txt = stdout_bytes.decode()  # convert bytestrings to unicode strings
                stdout = stdout_txt.split("\n")
                for line in stdout:
                    if "Version" in line:
                        version = re.findall(r"\d+\.\d+\.\d+", line)[0]
        except OSError as error:
            # pylint: disable=raise-missing-from
            raise InvalidCompilation(error)

    elif compiler in ["solc-js"]:
        cmd = ["solcjs", "--version"]
        try:
            with subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=cwd,
                executable=shutil.which(cmd[0]),
            ) as process:
                stdout_bytes, _ = process.communicate()
                stdout_txt = stdout_bytes.decode()  # convert bytestrings to unicode strings
                version = re.findall(r"\d+\.\d+\.\d+", stdout_txt)[0]
        except OSError as error:
            # pylint: disable=raise-missing-from
            raise InvalidCompilation(error)

    else:
        raise InvalidCompilation(f"Solidity version not found {compiler}")

    return version


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
