"""
Standard crytic-compile export
"""
import json
import os
from collections import defaultdict
from pathlib import Path
from typing import TYPE_CHECKING, Dict, List, Tuple, Type, Any

from crytic_compile.compilation_unit import CompilationUnit
from crytic_compile.compiler.compiler import CompilerVersion
from crytic_compile.platform import Type as PlatformType
from crytic_compile.platform.abstract_platform import AbstractPlatform
from crytic_compile.utils.naming import Filename

# Cycle dependency
from crytic_compile.utils.natspec import Natspec

if TYPE_CHECKING:
    from crytic_compile import CryticCompile


def export_to_standard(crytic_compile: "CryticCompile", **kwargs: str) -> List[str]:
    """Export the project to the standard crytic compile format

    Args:
        crytic_compile (CryticCompile): CryticCompile object to export
        **kwargs: optional arguments. Used: "export_dir"

    Returns:
        List[str]: List of files generated
    """
    # Obtain objects to represent each contract

    output = generate_standard_export(crytic_compile)

    export_dir = kwargs.get("export_dir", "crytic-export")
    if not os.path.exists(export_dir):
        os.makedirs(export_dir)

    target = (
        "contracts"
        if os.path.isdir(crytic_compile.target)
        else Path(crytic_compile.target).parts[-1]
    )

    path = os.path.join(export_dir, f"{target}.json")
    with open(path, "w", encoding="utf8") as file_desc:
        json.dump(output, file_desc)

    return [path]


class Standard(AbstractPlatform):
    """
    Standard platform (crytic-compile specific)
    """

    NAME = "Standard"
    PROJECT_URL = "https://github.com/crytic/crytic-compile"
    TYPE = PlatformType.STANDARD

    HIDE = True

    def __init__(self, target: str, **kwargs: str):
        """Init the Standard platform

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Not used

        """
        super().__init__(str(target), **kwargs)
        self._underlying_platform: Type[AbstractPlatform] = Standard
        self._unit_tests: List[str] = []

    def compile(self, crytic_compile: "CryticCompile", **_kwargs: str) -> None:
        """Compile the file (load the file for the Standard platform) and populates the CryticCompile object

        Args:
            crytic_compile (CryticCompile): Associated CryticCompile
            **_kwargs: optional arguments. Not used

        """
        # pylint: disable=import-outside-toplevel
        from crytic_compile.crytic_compile import get_platforms

        with open(self._target, encoding="utf8") as file_desc:
            loaded_json = json.load(file_desc)
        (underlying_type, unit_tests) = load_from_compile(crytic_compile, loaded_json)
        underlying_type = PlatformType(underlying_type)
        platforms: List[Type[AbstractPlatform]] = get_platforms()
        platform = next((p for p in platforms if p.TYPE == underlying_type), Standard)
        self._underlying_platform = platform
        self._unit_tests = unit_tests

    def clean(self, **_kwargs: str) -> None:
        """Clean compilation artifacts

        Args:
            **_kwargs: unused.
        """
        return

    @staticmethod
    def is_supported(target: str, **kwargs: str) -> bool:
        """Check if the target has the standard crytic-compile format

        Args:
            target (str): path to the target
            **kwargs: optional arguments. Used: "standard_ignore"

        Returns:
            bool: True if the target is a crytic-compile generated project
        """
        standard_ignore = kwargs.get("standard_ignore", False)
        if standard_ignore:
            return False
        if not Path(target).parts:
            return False
        return Path(target).parts[-1].endswith("_export.json")

    def is_dependency(self, path: str) -> bool:
        """Check if the target is a dependency
        This function always return false, the deps are handled by crytic_compile_dependencies

        Args:
            path (str): path to the target

        Returns:
            bool: Always False
        """
        # handled by crytic_compile_dependencies
        return False

    def _guessed_tests(self) -> List[str]:
        """Guess the potential unit tests commands

        Returns:
            List[str]: list of potential unit tests commands
        """
        return self._unit_tests

    @property
    def platform_name_used(self) -> str:
        """Return the name of the underlying platform used

        Returns:
            str: The name of the underlying platform used
        """
        return self._underlying_platform.NAME

    @property
    def platform_project_url_used(self) -> str:
        """Return the underlying platform project 's url

        Returns:
            str: Underlying platform project 's url
        """
        return self._underlying_platform.PROJECT_URL

    @property
    def platform_type_used(self) -> PlatformType:
        """Return the type of the underlying platform used

        Returns:
            PlatformType: Type of the underlying platform
        """
        return self._underlying_platform.TYPE


def _convert_filename_to_dict(filename: Filename) -> Dict:
    """Convert the filename to a dict containing the four filename fields

    Args:
        filename (Filename): Filename to convert

    Returns:
        Dict: Dict with the four filenames fields
    """
    return {
        "absolute": filename.absolute,
        "used": filename.used,
        "short": filename.short,
        "relative": filename.relative,
    }


def _convert_dict_to_filename(filename: Dict) -> Filename:
    """Convert a dict to a Filename
    This function should be called only on well formed json

    Args:
        filename (Dict): Json to convert

    Returns:
        Filename: Filename converted
    """

    assert "absolute" in filename
    assert "used" in filename
    assert "short" in filename
    assert "relative" in filename

    return Filename(
        absolute=filename["absolute"],
        relative=filename["relative"],
        short=filename["short"],
        used=filename["used"],
    )


def generate_standard_export(crytic_compile: "CryticCompile") -> Dict:
    """Convert the CryticCompile object to a json

    Args:
        crytic_compile (CryticCompile): CryticCompile object to export

    Returns:
        Dict: CryticCompile converted to a json
    """

    compilation_units = {}
    libraries_to_update = crytic_compile.libraries
    for key, compilation_unit in crytic_compile.compilation_units.items():
        source_unit_dict: Dict[str, Dict[str, Dict[str, Any]]] = {}

        for filename, source_unit in compilation_unit.source_units.items():
            source_unit_dict[filename.relative] = defaultdict(dict)
            source_unit_dict[filename.relative]["ast"] = source_unit.ast
            for contract_name in source_unit.contracts_names:
                libraries = source_unit.libraries_names_and_patterns(contract_name)
                source_unit_dict[filename.relative]["contracts"][contract_name] = {
                    "abi": source_unit.abi(contract_name),
                    "bin": source_unit.bytecode_init(contract_name, libraries_to_update),
                    "bin-runtime": source_unit.bytecode_runtime(contract_name, libraries_to_update),
                    "srcmap": ";".join(source_unit.srcmap_init(contract_name)),
                    "srcmap-runtime": ";".join(source_unit.srcmap_runtime(contract_name)),
                    "filenames": _convert_filename_to_dict(filename),
                    "libraries": dict(libraries) if libraries else {},
                    "is_dependency": crytic_compile.is_dependency(filename.absolute),
                    "userdoc": source_unit.natspec[contract_name].userdoc.export(),
                    "devdoc": source_unit.natspec[contract_name].devdoc.export(),
                }

        # Create our root object to contain the contracts and other information.

        compiler: Dict = {}
        if compilation_unit.compiler_version:
            compiler = {
                "compiler": compilation_unit.compiler_version.compiler,
                "version": compilation_unit.compiler_version.version,
                "optimized": compilation_unit.compiler_version.optimized,
            }

        compilation_units[key] = {
            "compiler": compiler,
            "source_units": source_unit_dict,
            "filenames": [
                _convert_filename_to_dict(filename) for filename in compilation_unit.filenames
            ],
        }

    output = {
        "compilation_units": compilation_units,
        "package": crytic_compile.package,
        "working_dir": str(crytic_compile.working_dir),
        "type": int(crytic_compile.platform.platform_type_used),
        "unit_tests": crytic_compile.platform.guessed_tests(),
        "crytic_version": "0.0.2",
    }
    return output


def _load_from_compile_legacy1(crytic_compile: "CryticCompile", loaded_json: Dict) -> None:
    """Load from old (old) export

    Args:
        crytic_compile (CryticCompile): CryticCompile object to populate
        loaded_json (Dict): Json representation of the CryticCompile object
    """
    compilation_unit = CompilationUnit(crytic_compile, "legacy")
    compilation_unit.compiler_version = CompilerVersion(
        compiler=loaded_json["compiler"]["compiler"],
        version=loaded_json["compiler"]["version"],
        optimized=loaded_json["compiler"]["optimized"],
    )

    if "filenames" in loaded_json:
        compilation_unit.filenames = [
            _convert_dict_to_filename(filename) for filename in loaded_json["filenames"]
        ]

    for path, ast in loaded_json["asts"].items():
        # The following might create lookup issue?
        filename = crytic_compile.filename_lookup(path)
        source_unit = compilation_unit.create_source_unit(filename)
        source_unit.ast = ast

    for contract_name, contract in loaded_json["contracts"].items():
        filename = _convert_dict_to_filename(contract["filenames"])
        compilation_unit.filename_to_contracts[filename].add(contract_name)
        source_unit = compilation_unit.create_source_unit(filename)

        source_unit.add_contract_name(contract_name)
        source_unit.abis[contract_name] = contract["abi"]
        source_unit.bytecodes_init[contract_name] = contract["bin"]
        source_unit.bytecodes_runtime[contract_name] = contract["bin-runtime"]
        source_unit.srcmaps_init[contract_name] = contract["srcmap"].split(";")
        source_unit.srcmaps_runtime[contract_name] = contract["srcmap-runtime"].split(";")
        source_unit.libraries[contract_name] = contract["libraries"]

        userdoc = contract.get("userdoc", {})
        devdoc = contract.get("devdoc", {})
        source_unit.natspec[contract_name] = Natspec(userdoc, devdoc)

        if contract["is_dependency"]:
            compilation_unit.crytic_compile.dependencies.add(filename.absolute)
            compilation_unit.crytic_compile.dependencies.add(filename.relative)
            compilation_unit.crytic_compile.dependencies.add(filename.short)
            compilation_unit.crytic_compile.dependencies.add(filename.used)


def _load_from_compile_legacy2(crytic_compile: "CryticCompile", loaded_json: Dict) -> None:
    """Load from old (old) export

    Args:
        crytic_compile (CryticCompile): CryticCompile object to populate
        loaded_json (Dict): Json representation of the CryticCompile object
    """

    for key, compilation_unit_json in loaded_json["compilation_units"].items():
        compilation_unit = CompilationUnit(crytic_compile, key)
        compilation_unit.compiler_version = CompilerVersion(
            compiler=compilation_unit_json["compiler"]["compiler"],
            version=compilation_unit_json["compiler"]["version"],
            optimized=compilation_unit_json["compiler"]["optimized"],
        )

        if "filenames" in compilation_unit_json:
            compilation_unit.filenames = [
                _convert_dict_to_filename(filename)
                for filename in compilation_unit_json["filenames"]
            ]

        for path, ast in loaded_json["asts"].items():
            # The following might create lookup issue?
            filename = crytic_compile.filename_lookup(path)
            source_unit = compilation_unit.create_source_unit(filename)
            source_unit.ast = ast

        for contract_name, contract in compilation_unit_json["contracts"].items():

            filename = Filename(
                absolute=contract["filenames"]["absolute"],
                relative=contract["filenames"]["relative"],
                short=contract["filenames"]["short"],
                used=contract["filenames"]["used"],
            )
            compilation_unit.filename_to_contracts[filename].add(contract_name)

            source_unit = compilation_unit.create_source_unit(filename)
            source_unit.add_contract_name(contract_name)
            source_unit.abis[contract_name] = contract["abi"]
            source_unit.bytecodes_init[contract_name] = contract["bin"]
            source_unit.bytecodes_runtime[contract_name] = contract["bin-runtime"]
            source_unit.srcmaps_init[contract_name] = contract["srcmap"].split(";")
            source_unit.srcmaps_runtime[contract_name] = contract["srcmap-runtime"].split(";")
            source_unit.libraries[contract_name] = contract["libraries"]

            userdoc = contract.get("userdoc", {})
            devdoc = contract.get("devdoc", {})
            source_unit.natspec[contract_name] = Natspec(userdoc, devdoc)

            if contract["is_dependency"]:
                crytic_compile.dependencies.add(filename.absolute)
                crytic_compile.dependencies.add(filename.relative)
                crytic_compile.dependencies.add(filename.short)
                crytic_compile.dependencies.add(filename.used)


def _load_from_compile_0_0_1(crytic_compile: "CryticCompile", loaded_json: Dict) -> None:
    for key, compilation_unit_json in loaded_json["compilation_units"].items():
        compilation_unit = CompilationUnit(crytic_compile, key)
        compilation_unit.compiler_version = CompilerVersion(
            compiler=compilation_unit_json["compiler"]["compiler"],
            version=compilation_unit_json["compiler"]["version"],
            optimized=compilation_unit_json["compiler"]["optimized"],
        )

        compilation_unit.filenames = [
            _convert_dict_to_filename(filename) for filename in compilation_unit_json["filenames"]
        ]

        for path, ast in compilation_unit_json["asts"].items():
            # The following might create lookup issue?
            filename = crytic_compile.filename_lookup(path)
            source_unit = compilation_unit.create_source_unit(filename)
            source_unit.ast = ast

        for contracts_data in compilation_unit_json["contracts"].values():
            for contract_name, contract in contracts_data.items():

                filename = Filename(
                    absolute=contract["filenames"]["absolute"],
                    relative=contract["filenames"]["relative"],
                    short=contract["filenames"]["short"],
                    used=contract["filenames"]["used"],
                )
                compilation_unit.filename_to_contracts[filename].add(contract_name)
                source_unit = compilation_unit.create_source_unit(filename)
                source_unit.add_contract_name(contract_name)
                source_unit.abis[contract_name] = contract["abi"]
                source_unit.bytecodes_init[contract_name] = contract["bin"]
                source_unit.bytecodes_runtime[contract_name] = contract["bin-runtime"]
                source_unit.srcmaps_init[contract_name] = contract["srcmap"].split(";")
                source_unit.srcmaps_runtime[contract_name] = contract["srcmap-runtime"].split(";")
                source_unit.libraries[contract_name] = contract["libraries"]

                userdoc = contract.get("userdoc", {})
                devdoc = contract.get("devdoc", {})
                source_unit.natspec[contract_name] = Natspec(userdoc, devdoc)

                if contract["is_dependency"]:
                    crytic_compile.dependencies.add(filename.absolute)
                    crytic_compile.dependencies.add(filename.relative)
                    crytic_compile.dependencies.add(filename.short)
                    crytic_compile.dependencies.add(filename.used)


def _load_from_compile_current(crytic_compile: "CryticCompile", loaded_json: Dict) -> None:
    for key, compilation_unit_json in loaded_json["compilation_units"].items():
        compilation_unit = CompilationUnit(crytic_compile, key)
        compilation_unit.compiler_version = CompilerVersion(
            compiler=compilation_unit_json["compiler"]["compiler"],
            version=compilation_unit_json["compiler"]["version"],
            optimized=compilation_unit_json["compiler"]["optimized"],
        )

        compilation_unit.filenames = [
            _convert_dict_to_filename(filename) for filename in compilation_unit_json["filenames"]
        ]

        for filename_str, source_unit_data in compilation_unit_json["source_units"].items():
            filename = compilation_unit.filename_lookup(filename_str)
            source_unit = compilation_unit.create_source_unit(filename)

            for contract_name, contract in source_unit_data.get("contracts", {}).items():
                compilation_unit.filename_to_contracts[filename].add(contract_name)

                source_unit = compilation_unit.create_source_unit(filename)
                source_unit.add_contract_name(contract_name)
                source_unit.abis[contract_name] = contract["abi"]
                source_unit.bytecodes_init[contract_name] = contract["bin"]
                source_unit.bytecodes_runtime[contract_name] = contract["bin-runtime"]
                source_unit.srcmaps_init[contract_name] = contract["srcmap"].split(";")
                source_unit.srcmaps_runtime[contract_name] = contract["srcmap-runtime"].split(";")
                source_unit.libraries[contract_name] = contract["libraries"]

                userdoc = contract.get("userdoc", {})
                devdoc = contract.get("devdoc", {})
                source_unit.natspec[contract_name] = Natspec(userdoc, devdoc)

                if contract["is_dependency"]:
                    crytic_compile.dependencies.add(filename.absolute)
                    crytic_compile.dependencies.add(filename.relative)
                    crytic_compile.dependencies.add(filename.short)
                    crytic_compile.dependencies.add(filename.used)

            source_unit.ast = source_unit_data["ast"]


def load_from_compile(crytic_compile: "CryticCompile", loaded_json: Dict) -> Tuple[int, List[str]]:
    """Load from a standard crytic compile json
    This function must be called on well-formed json

    Args:
        crytic_compile (CryticCompile): CryticCompile object to populate
        loaded_json (Dict): Json to load

    Returns:
        Tuple[int, List[str]]: (underlying platform types, guessed unit tests)
    """
    crytic_compile.package_name = loaded_json.get("package", None)
    if "compilation_units" not in loaded_json:
        _load_from_compile_legacy1(crytic_compile, loaded_json)

    elif "crytic_version" not in loaded_json:
        _load_from_compile_legacy2(crytic_compile, loaded_json)

    elif loaded_json["crytic_version"] == "0.0.1":
        _load_from_compile_0_0_1(crytic_compile, loaded_json)
    else:
        _load_from_compile_current(crytic_compile, loaded_json)

    crytic_compile.working_dir = loaded_json["working_dir"]

    return loaded_json["type"], loaded_json.get("unit_tests", [])
