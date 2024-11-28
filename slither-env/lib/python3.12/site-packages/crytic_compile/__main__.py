"""
This is the Slither cli script
"""
import argparse
from importlib.metadata import version
import json
import logging
import os
import sys
from typing import TYPE_CHECKING, Any, Optional

from crytic_compile.crytic_compile import compile_all, get_platforms
from crytic_compile.cryticparser import DEFAULTS_FLAG_IN_CONFIG, cryticparser
from crytic_compile.platform import InvalidCompilation
from crytic_compile.platform.all_export import PLATFORMS_EXPORT
from crytic_compile.utils.zip import ZIP_TYPES_ACCEPTED, save_to_zip

if TYPE_CHECKING:
    from crytic_compile import CryticCompile


logging.basicConfig()
LOGGER = logging.getLogger("CryticCompile")
LOGGER.setLevel(logging.INFO)


def parse_args() -> argparse.Namespace:
    """Create a argparse object and parse the arguments

    Returns:
        argparse.Namespace: parsed arguments
    """
    # Create our argument parser
    parser = argparse.ArgumentParser(
        description="""crytic-compile. For usage information,
see https://github.com/crytic/crytic-compile/wiki""",
        usage="crytic-compile contract.sol [flag]",
    )

    # Add arguments
    parser.add_argument("target", help="contract.sol")

    parser.add_argument(
        "--config-file",
        help="Provide a config file (default: crytic_compile.config.json)",
        action="store",
        dest="config_file",
        default="crytic_compile.config.json",
    )

    parser.add_argument(
        "--export-format",
        help=f"""Export json with non crytic-compile format
            (default None. Accepted: ({", ".join(list(PLATFORMS_EXPORT))})""",
        action="store",
        dest="export_format",
        default=None,
    )

    parser.add_argument(
        "--export-formats",
        help="Comma-separated list of export format, defaults to None",
        action="store",
        dest="export_formats",
        default=None,
    )

    parser.add_argument(
        "--export-dir",
        help="Export directory (default: crytic-export)",
        action="store",
        dest="export_dir",
        default=DEFAULTS_FLAG_IN_CONFIG["export_dir"],
    )

    parser.add_argument(
        "--export-zip",
        help="Export all the projects to a zip file",
        action="store",
        dest="export_to_zip",
        default=None,
    )

    parser.add_argument(
        "--export-zip-type",
        help=f"Zip compression type. One of {','.join(ZIP_TYPES_ACCEPTED.keys())}. Default lzma",
        action="store",
        dest="export_to_zip_type",
        default=None,
    )

    parser.add_argument(
        "--print-filenames",
        help="Print all the filenames",
        action="store_true",
        dest="print_filename",
        default=False,
    )

    parser.add_argument(
        "--print-libraries",
        help="Print all the libraries info",
        action="store_true",
        dest="print_libraries",
        default=False,
    )

    parser.add_argument(
        "--version",
        help="displays the current version",
        version=version("crytic-compile"),
        action="version",
    )

    parser.add_argument(
        "--supported-platforms",
        help="Shows the platforms supported",
        action=ShowPlatforms,
        nargs=0,
        default=False,
    )

    cryticparser.init(parser)
    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()

    # If there is a config file provided, update the values with the one in the config file
    if os.path.isfile(args.config_file):
        try:
            with open(args.config_file, encoding="utf8") as f_config:
                config = json.load(f_config)
                for key, elem in config.items():
                    if key not in DEFAULTS_FLAG_IN_CONFIG:
                        LOGGER.info("%s has an unknown key: %s : %s", args.config_file, key, elem)
                        continue
                    if getattr(args, key) == DEFAULTS_FLAG_IN_CONFIG[key]:
                        setattr(args, key, elem)
        except json.decoder.JSONDecodeError as exception:
            LOGGER.error(
                "Impossible to read %s, please check the file %s", args.config_file, exception
            )

    return args


class ShowPlatforms(argparse.Action):  # pylint: disable=too-few-public-methods
    """
    This class is used to print the different platforms supported to the log
    See --supported-platforms
    """

    def __call__(
        self,
        parser: argparse.ArgumentParser,
        args: Any,
        values: Any,
        option_string: Optional[str] = None,
    ) -> None:
        """Action performed

        Args:
            parser (argparse.ArgumentParser): argument parser
            args (Any):  not used
            values (Any): not used
            option_string (Optional[str], optional): not used. Defaults to None.
        """
        platforms = get_platforms()
        LOGGER.info("\n" + "\n".join([f"- {x.NAME}: {x.PROJECT_URL}" for x in platforms]))
        parser.exit()


def _print_filenames(compilation: "CryticCompile") -> None:
    """Print the filenames

    Args:
        compilation (CryticCompile): CryticCompile project
    """
    for compilation_id, compilation_unit in compilation.compilation_units.items():
        print(
            f"Compilation unit: {compilation_id} solc {compilation_unit.compiler_version.version})"
        )
        for filename, contracts in compilation_unit.filename_to_contracts.items():
            for contract in contracts:
                print(f"\t{contract} -> \n\tAbsolute: {filename.absolute}")
        for filename in compilation_unit.filenames:
            print(f"\t{filename.absolute}")
            print(f"\t\tRelative: {filename.relative}")
            print(f"\t\tShort: {filename.short}")
            print(f"\t\tUsed: {filename.used}")


def _print_libraries(compilation: "CryticCompile") -> None:
    for compilation_id, compilation_unit in compilation.compilation_units.items():
        print(
            f"Compilation unit: {compilation_id} solc {compilation_unit.compiler_version.version})"
        )

        libraries_to_update = compilation.libraries

        print(libraries_to_update)
        for source_unit in compilation_unit.source_units.values():
            for contract in source_unit.contracts_names_without_libraries:
                libs = source_unit.libraries_names(contract)
                if libs:
                    print(f"## {contract}")
                    print(f"\tuses: {libs}")
                    print(
                        f"\truntime bytecode: {source_unit.bytecode_runtime(contract, libraries_to_update)}"
                    )


def main() -> None:
    """Main function run from the cli"""
    args = parse_args()
    try:
        # Compile all specified (possibly glob patterned) targets.
        compilations = compile_all(**vars(args))

        # Perform relevant tasks for each compilation
        # print(compilations[0].compilation_units)
        for compilation in compilations:
            # Print the filename of each contract (no duplicates).
            if args.print_filename:
                _print_filenames(compilation)
            if args.print_libraries:
                _print_libraries(compilation)
            if args.export_format:
                compilation.export(**vars(args))

            if args.export_formats:
                for export_format in args.export_formats.split(","):
                    args.export_format = export_format
                    compilation.export(**vars(args))

        if args.export_to_zip:
            save_to_zip(compilations, args.export_to_zip, args.export_to_zip_type)

    except InvalidCompilation as exception:
        LOGGER.error(exception)
        sys.exit(-1)


if __name__ == "__main__":
    main()
