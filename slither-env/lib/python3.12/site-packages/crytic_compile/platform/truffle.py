"""
Truffle platform
"""
import glob
import json
import logging
import os
import platform
import re
import shutil
import subprocess
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Optional, Tuple

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform import solc
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.platform.exceptions import InvalidCompilation
from crytic_compile.platform.types import Type
from crytic_compile.utils.naming import convert_filename
from crytic_compile.utils.natspec import Natspec

# Handle cycle
if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


def export_to_truffle(crytic_compile: "CryticCompile", **kwargs: str) -> List[str]:
    """Export to the truffle format

    Args:
        crytic_compile (CryticCompile): CryticCompile object to export
        **kwargs: optional arguments. Used: "export_dir"

    Raises:
        InvalidCompilation: If there are more than 1 compilation unit

    Returns:
        List[str]: Singleton with the generated directory
    """
    # Get our export directory, if it's set, we create the path.
    export_dir = kwargs.get("export_dir", "crytic-export")
    if export_dir and not os.path.exists(export_dir):
        os.makedirs(export_dir)

    compilation_units = list(crytic_compile.compilation_units.values())
    if len(compilation_units) != 1:
        raise InvalidCompilation("Truffle export require 1 compilation unit")
    compilation_unit = compilation_units[0]

    # Loop for each contract filename.

    libraries = compilation_unit.crytic_compile.libraries

    results: List[Dict] = []
    for source_unit in compilation_unit.source_units.values():
        for contract_name in source_unit.contracts_names:
            # Create the informational object to output for this contract
            output = {
                "contractName": contract_name,
                "abi": source_unit.abi(contract_name),
                "bytecode": "0x" + source_unit.bytecode_init(contract_name, libraries),
                "deployedBytecode": "0x" + source_unit.bytecode_runtime(contract_name, libraries),
                "ast": source_unit.ast,
                "userdoc": source_unit.natspec[contract_name].userdoc.export(),
                "devdoc": source_unit.natspec[contract_name].devdoc.export(),
            }
            results.append(output)

            # If we have an export directory, export it.

            path = os.path.join(export_dir, contract_name + ".json")
            with open(path, "w", encoding="utf8") as file_desc:
                json.dump(output, file_desc)

    return [export_dir]


class Truffle(AbstractPlatform):
    """
    Truffle platform
    """

    NAME = "Truffle"
    PROJECT_URL = "https://github.com/trufflesuite/truffle"
    TYPE = Type.TRUFFLE

    # pylint: disable=too-many-locals,too-many-statements,too-many-branches
    def compile(self, crytic_compile: "CryticCompile", **kwargs: str) -> None:
        """Compile

        Args:
            crytic_compile (CryticCompile): CryticCompile object to populate
            **kwargs: optional arguments. Used "truffle_build_directory", "truffle_ignore_compile", "ignore_compile",
                "truffle_version", "npx_disable"

        Raises:
            InvalidCompilation: If truffle failed to run
        """

        build_directory = kwargs.get("truffle_build_directory", os.path.join("build", "contracts"))
        truffle_ignore_compile = kwargs.get("truffle_ignore_compile", False) or kwargs.get(
            "ignore_compile", False
        )
        truffle_version = kwargs.get("truffle_version", None)
        # crytic_compile.type = Type.TRUFFLE
        # Truffle on windows has naming conflicts where it will invoke truffle.js directly instead
        # of truffle.cmd (unless in powershell or git bash).
        # The cleanest solution is to explicitly call
        # truffle.cmd. Reference:
        # https://truffleframework.com/docs/truffle/reference/configuration#resolving-naming-conflicts-on-windows

        truffle_overwrite_config = kwargs.get("truffle_overwrite_config", False)

        if platform.system() == "Windows":
            base_cmd = ["truffle.cmd"]
        elif kwargs.get("npx_disable", False):
            base_cmd = ["truffle"]
        else:
            base_cmd = ["npx", "truffle"]
            if truffle_version:
                if truffle_version.startswith("truffle"):
                    base_cmd = ["npx", truffle_version]
                else:
                    base_cmd = ["npx", f"truffle@{truffle_version}"]
            elif os.path.isfile(os.path.join(self._target, "package.json")):
                with open(os.path.join(self._target, "package.json"), encoding="utf8") as file_desc:
                    package = json.load(file_desc)
                    if "devDependencies" in package:
                        if "truffle" in package["devDependencies"]:
                            version = package["devDependencies"]["truffle"]
                            if version.startswith("^"):
                                version = version[1:]
                            truffle_version = f"truffle@{version}"
                            base_cmd = ["npx", truffle_version]
                    if "dependencies" in package:
                        if "truffle" in package["dependencies"]:
                            version = package["dependencies"]["truffle"]
                            if version.startswith("^"):
                                version = version[1:]
                            truffle_version = f"truffle@{version}"
                            base_cmd = ["npx", truffle_version]

        if not truffle_ignore_compile:
            cmd = base_cmd + ["compile", "--all"]

            LOGGER.info(
                "'%s' running (use --truffle-version truffle@x.x.x to use specific version)",
                " ".join(cmd),
            )

            config_used = None
            config_saved = None
            if truffle_overwrite_config:
                overwritten_version = kwargs.get("truffle_overwrite_version", None)
                # If the version is not provided, we try to guess it with the config file
                if overwritten_version is None:
                    version_from_config = _get_version_from_config(self._target)
                    if version_from_config:
                        overwritten_version, _ = version_from_config

                # Save the config file, and write our temporary config
                config_used, config_saved = _save_config(Path(self._target))
                if config_used is None:
                    config_used = Path("truffle-config.js")
                _write_config(Path(self._target), config_used, overwritten_version)

            with subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=self._target,
                executable=shutil.which(cmd[0]),
            ) as process:

                stdout_bytes, stderr_bytes = process.communicate()
                stdout, stderr = (
                    stdout_bytes.decode(errors="backslashreplace"),
                    stderr_bytes.decode(errors="backslashreplace"),
                )  # convert bytestrings to unicode strings

                if truffle_overwrite_config:
                    assert config_used
                    _reload_config(Path(self._target), config_saved, config_used)

                LOGGER.info(stdout)
                if stderr:
                    LOGGER.error(stderr)
        if not os.path.isdir(os.path.join(self._target, build_directory)):
            if os.path.isdir(os.path.join(self._target, "node_modules")):
                raise InvalidCompilation(
                    f"External dependencies {build_directory} {self._target} not found, please install them. (npm install)"
                )
            raise InvalidCompilation("`truffle compile` failed. Can you run it?")
        filenames = glob.glob(os.path.join(self._target, build_directory, "*.json"))

        optimized = None

        version = None
        compiler = None
        compilation_unit = CompilationUnit(crytic_compile, str(self._target))

        for filename_txt in filenames:
            with open(filename_txt, encoding="utf8") as file_desc:
                target_loaded = json.load(file_desc)
                # pylint: disable=too-many-nested-blocks
                if optimized is None:
                    if "metadata" in target_loaded:
                        metadata = target_loaded["metadata"]
                        try:
                            metadata = json.loads(metadata)
                            if "settings" in metadata:
                                if "optimizer" in metadata["settings"]:
                                    if "enabled" in metadata["settings"]["optimizer"]:
                                        optimized = metadata["settings"]["optimizer"]["enabled"]
                        except json.decoder.JSONDecodeError:
                            pass

                userdoc = target_loaded.get("userdoc", {})
                devdoc = target_loaded.get("devdoc", {})
                natspec = Natspec(userdoc, devdoc)

                if not "ast" in target_loaded:
                    continue

                filename = target_loaded["ast"]["absolutePath"]

                # Since truffle 5.3.14, the filenames start with "project:"
                # See https://github.com/crytic/crytic-compile/issues/199
                if filename.startswith("project:"):
                    filename = "." + filename[len("project:") :]

                try:
                    filename = convert_filename(
                        filename, _relative_to_short, crytic_compile, working_dir=self._target
                    )
                except InvalidCompilation as i:
                    txt = str(i)
                    txt += "\nConsider removing the build/contracts content (rm build/contracts/*)"
                    # pylint: disable=raise-missing-from
                    raise InvalidCompilation(txt)

                source_unit = compilation_unit.create_source_unit(filename)

                source_unit.ast = target_loaded["ast"]

                contract_name = target_loaded["contractName"]
                source_unit.natspec[contract_name] = natspec
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

                if compiler is None:
                    compiler = target_loaded.get("compiler", {}).get("name", None)
                if version is None:
                    version = target_loaded.get("compiler", {}).get("version", None)
                    if "+" in version:
                        version = version[0 : version.find("+")]

        if version is None or compiler is None:
            version_from_config = _get_version_from_config(self._target)
            if version_from_config:
                version, compiler = version_from_config
            else:
                version, compiler = _get_version(base_cmd, cwd=self._target)

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
        """Check if the target is a truffle project

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used: "truffle_ignore"

        Returns:
            bool: True if the target is a truffle project
        """
        truffle_ignore = kwargs.get("truffle_ignore", False)
        if truffle_ignore:
            return False

        return os.path.isfile(os.path.join(target, "truffle.js")) or os.path.isfile(
            os.path.join(target, "truffle-config.js")
        )

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
        ret = "node_modules" in Path(path).parts
        self._cached_dependencies[path] = ret
        return ret

    # pylint: disable=no-self-use
    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: The guessed unit tests commands
        """
        return ["truffle test"]


def _get_version_from_config(target: str) -> Optional[Tuple[str, str]]:
    """Naive check on the truffleconfig file to get the version

    Args:
        target (str): path to the project directory

    Returns:
        Optional[Tuple[str, str]]: (compiler version, compiler name)
    """
    config = Path(target, "truffle-config.js")
    if not config.exists():
        config = Path(target, "truffle.js")
        if not config.exists():
            return None
    with open(config, "r", encoding="utf8") as config_f:
        config_buffer = config_f.read()

    # The config is a javascript file
    # Use a naive regex to match the solc version
    match = re.search(r'solc: {[ ]*\n[ ]*version: "([0-9\.]*)', config_buffer)
    if match:
        if match.groups():
            version = match.groups()[0]
            return version, "solc-js"
    return None


def _get_version(truffle_call: List[str], cwd: str) -> Tuple[str, str]:
    """Get the compiler version

    Args:
        truffle_call (List[str]): Command to run truffle
        cwd (str): Working directory to run truffle

    Raises:
        InvalidCompilation: If truffle failed, or the solidity version was not found

    Returns:
        Tuple[str, str]: (compiler version, compiler name)
    """
    cmd = truffle_call + ["version"]
    try:
        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            executable=shutil.which(cmd[0]),
        ) as process:
            sstdout, _ = process.communicate()
            ssstdout = sstdout.decode()  # convert bytestrings to unicode strings
            if not ssstdout:
                raise InvalidCompilation("Truffle failed to run: 'truffle version'")
            stdout = ssstdout.split("\n")
            for line in stdout:
                if "Solidity" in line:
                    if "native" in line:
                        return solc.get_version("solc", {}), "solc-native"
                    version = re.findall(r"\d+\.\d+\.\d+", line)[0]
                    compiler = re.findall(r"(solc[a-z\-]*)", line)
                    if len(compiler) > 0:
                        return version, compiler[0]

            raise InvalidCompilation(f"Solidity version not found {stdout}")
    except OSError as error:
        # pylint: disable=raise-missing-from
        raise InvalidCompilation(f"Truffle failed: {error}")


def _save_config(cwd: Path) -> Tuple[Optional[Path], Optional[Path]]:
    """Save truffle-config.js / truffle.js to a temporary file.

    Args:
        cwd (Path): Working directory

    Returns:
        Tuple[Optional[Path], Optional[Path]]: (original_config_name, temporary_file). None if there was no config file
    """
    unique_filename = str(uuid.uuid4())
    while Path(cwd, unique_filename).exists():
        unique_filename = str(uuid.uuid4())

    if Path(cwd, "truffle-config.js").exists():
        shutil.move(str(Path(cwd, "truffle-config.js")), str(Path(cwd, unique_filename)))
        return Path("truffle-config.js"), Path(unique_filename)

    if Path(cwd, "truffle.js").exists():
        shutil.move(str(Path(cwd, "truffle.js")), str(Path(cwd, unique_filename)))
        return Path("truffle.js"), Path(unique_filename)
    return None, None


def _reload_config(cwd: Path, original_config: Optional[Path], tmp_config: Path) -> None:
    """Restore the original config

    Args:
        cwd (Path): Working directory
        original_config (Optional[Path]): Original config saved
        tmp_config (Path): Temporary config
    """
    os.remove(Path(cwd, tmp_config))
    if original_config is not None:
        shutil.move(str(Path(cwd, original_config)), str(Path(cwd, tmp_config)))


def _write_config(cwd: Path, original_config: Path, version: Optional[str]) -> None:
    """Write the config file

    Args:
        cwd (Path): Working directory
        original_config (Path): Original config saved
        version (Optional[str]): Solc version
    """
    txt = ""
    if version:
        txt = f"""
    module.exports = {{
      compilers: {{
        solc: {{
          version: "{version}"
        }}
      }}
    }}
    """
    with open(Path(cwd, original_config), "w", encoding="utf8") as f:
        f.write(txt)


def _relative_to_short(relative: Path) -> Path:
    """Convert the relative path to its short version

    Args:
        relative (Path): Path to convert

    Returns:
        Path: Converted path
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
