"""
Module handling NPM related features
"""
import json
from pathlib import Path
from typing import TYPE_CHECKING, Optional, Union, Dict

# Cycle dependency
if TYPE_CHECKING:
    from crytic_compile.platform.solc_standard_json import SolcStandardJson


def get_package_name(target_txt: Union[str, "SolcStandardJson"]) -> Optional[str]:
    """Return the npm package's name

    Args:
        target_txt (Union[str,SolcStandardJson): path to the target

    Returns:
        Optional[str]: npm package name
    """

    # Verify the target path is a string (exported zip archives are lists)
    if not isinstance(target_txt, str):
        return None

    # Obtain the path the target string represents
    try:
        target = Path(target_txt)
        if target.is_dir():
            package = Path(target, "package.json")
            if package.exists():
                with open(package, "r", encoding="utf8") as file_desc:
                    try:
                        package_dict: Dict[str, str] = json.load(file_desc)
                        return package_dict.get("name", None)
                    except json.JSONDecodeError:
                        return None
        return None

    except (OSError, ValueError):
        # Can happen if the target is a very large string, is_dir will throw an exception
        return None
