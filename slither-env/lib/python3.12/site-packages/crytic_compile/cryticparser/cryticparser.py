"""
Module handling the cli arguments

Call cryticparser.init(parser: ArgumentParser) to setup all the crytic-compile arguments in the argument parser
"""
from argparse import ArgumentParser

from crytic_compile.crytic_compile import get_platforms
from crytic_compile.cryticparser import DEFAULTS_FLAG_IN_CONFIG


def init(parser: ArgumentParser) -> None:
    """Add crytic-compile arguments to the parser

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """

    group_compile = parser.add_argument_group("Compile options")

    platforms = get_platforms()

    group_compile.add_argument(
        "--compile-force-framework",
        help="Force the compile to a given framework "
        f"({','.join([x.NAME.lower() for x in platforms])})",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["compile_force_framework"],
    )

    group_compile.add_argument(
        "--compile-libraries",
        help='Libraries used for linking. Format: --compile-libraries "(name1, 0x00),(name2, 0x02)"',
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["compile_libraries"],
    )

    group_compile.add_argument(
        "--compile-remove-metadata",
        help="Remove the metadata from the bytecodes",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["compile_remove_metadata"],
    )

    group_compile.add_argument(
        "--compile-custom-build",
        help="Replace platform specific build command",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["compile_custom_build"],
    )

    group_compile.add_argument(
        "--ignore-compile",
        help="Do not run compile of any platform",
        action="store_true",
        dest="ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["ignore_compile"],
    )

    group_compile.add_argument(
        "--skip-clean",
        help="Do not attempt to clean before compiling with a platform",
        action="store_true",
        dest="skip_clean",
        default=DEFAULTS_FLAG_IN_CONFIG["skip_clean"],
    )

    _init_solc(parser)
    _init_truffle(parser)
    _init_embark(parser)
    _init_brownie(parser)
    _init_dapp(parser)
    _init_etherlime(parser)
    _init_etherscan(parser)
    _init_waffle(parser)
    _init_npx(parser)
    _init_buidler(parser)
    _init_hardhat(parser)
    _init_foundry(parser)


def _init_solc(parser: ArgumentParser) -> None:
    """Init solc arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """

    group_solc = parser.add_argument_group("Solc options")
    group_solc.add_argument(
        "--solc", help="solc path", action="store", default=DEFAULTS_FLAG_IN_CONFIG["solc"]
    )

    group_solc.add_argument(
        "--solc-remaps",
        help="Add remapping",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_remaps"],
    )

    group_solc.add_argument(
        "--solc-args",
        help="Add custom solc arguments. Example: --solc-args"
        ' "--allow-path /tmp --evm-version byzantium".',
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_args"],
    )

    group_solc.add_argument(
        "--solc-disable-warnings",
        help="Disable solc warnings",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_disable_warnings"],
    )

    group_solc.add_argument(
        "--solc-working-dir",
        help="Change the default working directory",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_working_dir"],
    )

    group_solc.add_argument(
        "--solc-solcs-select",
        help="Specify different solc version to try (env config). Depends on solc-select    ",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_solcs_select"],
    )

    group_solc.add_argument(
        "--solc-solcs-bin",
        help="Specify different solc version to try (path config)."
        " Example: --solc-solcs-bin solc-0.4.24,solc-0.5.3",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_solcs_bin"],
    )

    group_solc.add_argument(
        "--solc-standard-json",
        help="Compile all specified targets in a single compilation using solc standard json",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_standard_json"],
    )

    group_solc.add_argument(
        "--solc-force-legacy-json",
        help="Force the solc compiler to use the legacy json ast format over the compact json ast format",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["solc_force_legacy_json"],
    )


def _init_waffle(parser: ArgumentParser) -> None:
    """Init waffle arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_waffle = parser.add_argument_group("Waffle options")
    group_waffle.add_argument(
        "--waffle-ignore-compile",
        help="Do not run waffle compile",
        action="store_true",
        dest="waffle_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["waffle_ignore_compile"],
    )

    group_waffle.add_argument(
        "--waffle-config-file",
        help="Provide a waffle config file",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["waffle_config_file"],
    )


def _init_truffle(parser: ArgumentParser) -> None:
    """Init truffle arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_truffle = parser.add_argument_group("Truffle options")
    group_truffle.add_argument(
        "--truffle-ignore-compile",
        help="Do not run truffle compile",
        action="store_true",
        dest="truffle_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["truffle_ignore_compile"],
    )

    group_truffle.add_argument(
        "--truffle-build-directory",
        help="Use an alternative truffle build directory",
        action="store",
        dest="truffle_build_directory",
        default=DEFAULTS_FLAG_IN_CONFIG["truffle_build_directory"],
    )

    group_truffle.add_argument(
        "--truffle-version",
        help="Use a local Truffle version (with npx)",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["truffle_version"],
    )

    group_truffle.add_argument(
        "--truffle-overwrite-config",
        help="Use a simplified version of truffle-config.js for compilation",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["truffle_overwrite_config"],
    )

    group_truffle.add_argument(
        "--truffle-overwrite-version",
        help="Overwrite solc version in truffle-config.js (only if --truffle-overwrite-config)",
        action="store",
        default=DEFAULTS_FLAG_IN_CONFIG["truffle_overwrite_version"],
    )


def _init_embark(parser: ArgumentParser) -> None:
    """Init embark arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_embark = parser.add_argument_group("Embark options")
    group_embark.add_argument(
        "--embark-ignore-compile",
        help="Do not run embark build",
        action="store_true",
        dest="embark_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["embark_ignore_compile"],
    )

    group_embark.add_argument(
        "--embark-overwrite-config",
        help="Install @trailofbits/embark-contract-export and add it to embark.json",
        action="store_true",
        default=DEFAULTS_FLAG_IN_CONFIG["embark_overwrite_config"],
    )


def _init_brownie(parser: ArgumentParser) -> None:
    """Init brownie arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_brownie = parser.add_argument_group("Brownie options")
    group_brownie.add_argument(
        "--brownie-ignore-compile",
        help="Do not run brownie compile",
        action="store_true",
        dest="brownie_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["brownie_ignore_compile"],
    )


def _init_dapp(parser: ArgumentParser) -> None:
    """Init dapp arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_dapp = parser.add_argument_group("Dapp options")
    group_dapp.add_argument(
        "--dapp-ignore-compile",
        help="Do not run dapp build",
        action="store_true",
        dest="dapp_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["dapp_ignore_compile"],
    )


def _init_etherlime(parser: ArgumentParser) -> None:
    """Init etherlime arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_etherlime = parser.add_argument_group("Etherlime options")
    group_etherlime.add_argument(
        "--etherlime-ignore-compile",
        help="Do not run etherlime compile",
        action="store_true",
        dest="etherlime_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["etherlime_ignore_compile"],
    )

    group_etherlime.add_argument(
        "--etherlime-compile-arguments",
        help="Add arbitrary arguments to etherlime compile "
        "(note: [dir] is the the directory provided to crytic-compile)",
        action="store_true",
        dest="etherlime_compile_arguments",
        default=DEFAULTS_FLAG_IN_CONFIG["etherlime_compile_arguments"],
    )


def _init_etherscan(parser: ArgumentParser) -> None:
    """Init etherscan arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_etherscan = parser.add_argument_group("Etherscan options")
    group_etherscan.add_argument(
        "--etherscan-only-source-code",
        help="Only compile if the source code is available.",
        action="store_true",
        dest="etherscan_only_source_code",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_only_source_code"],
    )

    group_etherscan.add_argument(
        "--etherscan-only-bytecode",
        help="Only looks for bytecode.",
        action="store_true",
        dest="etherscan_only_bytecode",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_only_bytecode"],
    )

    group_etherscan.add_argument(
        "--etherscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="etherscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--arbiscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="arbiscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--polygonscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="polygonscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--test-polygonscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="test_polygonscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--avax-apikey",
        help="Etherscan API key.",
        action="store",
        dest="avax_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--ftmscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="ftmscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--bscan-apikey",
        help="Etherscan API key.",
        action="store",
        dest="bscan_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--optim-apikey",
        help="Optimistic API key.",
        action="store",
        dest="optim_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--base-apikey",
        help="Basescan API key.",
        action="store",
        dest="base_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--gno-apikey",
        help="Gnosisscan API key.",
        action="store",
        dest="gno_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--polyzk-apikey",
        help="zkEVM Polygonscan API key.",
        action="store",
        dest="polyzk_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--blast-apikey",
        help="Blastscan API key.",
        action="store",
        dest="blast_api_key",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_api_key"],
    )

    group_etherscan.add_argument(
        "--etherscan-export-directory",
        help="Directory in which to save the analyzed contracts.",
        action="store",
        dest="etherscan_export_dir",
        default=DEFAULTS_FLAG_IN_CONFIG["etherscan_export_directory"],
    )


def _init_npx(parser: ArgumentParser) -> None:
    """Init npx arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_npx = parser.add_argument_group("NPX options")
    group_npx.add_argument(
        "--npx-disable",
        help="Do not use npx",
        action="store_true",
        dest="npx_disable",
        default=DEFAULTS_FLAG_IN_CONFIG["npx_disable"],
    )


def _init_buidler(parser: ArgumentParser) -> None:
    """Init buidler arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_buidler = parser.add_argument_group("Buidler options")
    group_buidler.add_argument(
        "--buidler-ignore-compile",
        help="Do not run buidler compile",
        action="store_true",
        dest="buidler_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["buidler_ignore_compile"],
    )

    group_buidler.add_argument(
        "--buidler-cache-directory",
        help="Use an alternative buidler cache directory (default ./cache)",
        action="store",
        dest="buidler_cache_directory",
        default=DEFAULTS_FLAG_IN_CONFIG["buidler_cache_directory"],
    )

    group_buidler.add_argument(
        "--buidler-skip-directory-name-fix",
        help="Disable directory name fix (see https://github.com/crytic/crytic-compile/issues/116)",
        action="store_true",
        dest="buidler_skip_directory_name_fix",
        default=DEFAULTS_FLAG_IN_CONFIG["buidler_skip_directory_name_fix"],
    )


def _init_hardhat(parser: ArgumentParser) -> None:
    """Init hardhat arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_hardhat = parser.add_argument_group("Hardhat options")
    group_hardhat.add_argument(
        "--hardhat-ignore-compile",
        help="Do not run hardhat compile",
        action="store_true",
        dest="hardhat_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["hardhat_ignore_compile"],
    )

    group_hardhat.add_argument(
        "--hardhat-cache-directory",
        help="Use an alternative hardhat cache directory (default ./cache)",
        action="store",
        dest="hardhat_cache_directory",
        default=DEFAULTS_FLAG_IN_CONFIG["hardhat_cache_directory"],
    )

    group_hardhat.add_argument(
        "--hardhat-artifacts-directory",
        help="Use an alternative hardhat artifacts directory (default ./artifacts)",
        action="store",
        dest="hardhat_artifacts_directory",
        default=DEFAULTS_FLAG_IN_CONFIG["hardhat_artifacts_directory"],
    )


def _init_foundry(parser: ArgumentParser) -> None:
    """Init foundry arguments

    Args:
        parser (ArgumentParser): argparser where the cli flags are added
    """
    group_foundry = parser.add_argument_group("Foundry options")
    group_foundry.add_argument(
        "--foundry-ignore-compile",
        help="Do not run foundry compile",
        action="store_true",
        dest="foundry_ignore_compile",
        default=DEFAULTS_FLAG_IN_CONFIG["foundry_ignore_compile"],
    )

    group_foundry.add_argument(
        "--foundry-out-directory",
        help="Use an alternative out directory (default: out)",
        action="store",
        dest="foundry_out_directory",
        default=DEFAULTS_FLAG_IN_CONFIG["foundry_out_directory"],
    )

    group_foundry.add_argument(
        "--foundry-compile-all",
        help="Don't skip compiling test and script",
        action="store_true",
        dest="foundry_compile_all",
        default=DEFAULTS_FLAG_IN_CONFIG["foundry_compile_all"],
    )
