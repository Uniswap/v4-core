"""
Foundry platform
"""
import logging
import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, List, Optional, TypeVar

import json

from crytic_compile.platform.abstract_platform import AbstractPlatform, PlatformConfig
from crytic_compile.platform.types import Type
from crytic_compile.platform.hardhat import hardhat_like_parsing
from crytic_compile.utils.subprocess import run

# Handle cycle
if TYPE_CHECKING:
    from crytic_compile import CryticCompile

T = TypeVar("T")

LOGGER = logging.getLogger("CryticCompile")


class Foundry(AbstractPlatform):
    """
    Foundry platform
    """

    NAME = "Foundry"
    PROJECT_URL = "https://github.com/foundry-rs/foundry"
    TYPE = Type.FOUNDRY

    # pylint: disable=too-many-locals,too-many-statements,too-many-branches
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Compile

        Args:
            crytic_compile (CryticCompile): CryticCompile object to populate
            **kwargs: optional arguments. Used: "foundry_ignore_compile", "foundry_out_directory"

        """

        ignore_compile = kwargs.get("foundry_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )

        out_directory = kwargs.get("foundry_out_directory", "out")

        if ignore_compile:
            LOGGER.info(
                "--ignore-compile used, if something goes wrong, consider removing the ignore compile flag"
            )

        if not ignore_compile:
            compilation_command = [
                "forge",
                "build",
                "--build-info",
            ]

            compile_all = kwargs.get("foundry_compile_all", False)

            if not compile_all:
                foundry_config = self.config(self._target)
                if foundry_config:
                    compilation_command += [
                        "--skip",
                        f"*/{foundry_config.tests_path}/**",
                        f"*/{foundry_config.scripts_path}/**",
                        "--force",
                    ]

            run(
                compilation_command,
                cwd=self._target,
            )

        build_directory = Path(
            self._target,
            out_directory,
            "build-info",
        )

        hardhat_like_parsing(crytic_compile, self._target, build_directory, self._target)

    def clean(self, **kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **kwargs: optional arguments.
        """

        ignore_compile = kwargs.get("foundry_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )

        if ignore_compile:
            return

        run(["forge", "clean"], cwd=self._target)

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target is a foundry project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used: "foundry_ignore"

        Returns:
            bool: True if the target is a foundry project
        """
        if kwargs.get("foundry_ignore", False):
            return False

        return os.path.isfile(os.path.join(target, "foundry.toml"))

    @staticmethod
    def config(working_dir: str) -> Optional[PlatformConfig]:
        """Return configuration data that should be passed to solc, such as remappings.

        Args:
            working_dir (str): path to the working_dir

        Returns:
            Optional[PlatformConfig]: Platform configuration data such as optimization, remappings...
        """
        result = PlatformConfig()
        LOGGER.info("'forge config --json' running")
        json_config = json.loads(
            subprocess.run(
                ["forge", "config", "--json"], cwd=working_dir, stdout=subprocess.PIPE, check=True
            ).stdout
        )

        # Solc configurations
        result.solc_version = json_config.get("solc")
        result.via_ir = json_config.get("via_ir")
        result.allow_paths = json_config.get("allow_paths")
        result.offline = json_config.get("offline")
        result.evm_version = json_config.get("evm_version")
        result.optimizer = json_config.get("optimizer")
        result.optimizer_runs = json_config.get("optimizer_runs")
        result.remappings = json_config.get("remappings")

        # Foundry project configurations
        result.src_path = json_config.get("src")
        result.tests_path = json_config.get("test")
        result.libs_path = json_config.get("libs")
        result.scripts_path = json_config.get("script")

        return result

    # pylint: disable=no-self-use
    def is_dependency(self, path: str) -> bool:
        """Check if the path is a dependency

        Args:
            path (str): path to the target

        Returns:
            bool: True if the target is a dependency
        """
        if path in self._cached_dependencies:
            return self._cached_dependencies[path]
        ret = "lib" in Path(path).parts
        self._cached_dependencies[path] = ret
        return ret

    # pylint: disable=no-self-use
    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return ["forge test"]
