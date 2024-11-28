"""
Module handling unit-tests features
"""
import json
from pathlib import Path
from typing import List


def guess_tests(target: str) -> List[str]:
    """Try to guess the unit tests commands

    Args:
        target (str): path to the target

    Returns:
        List[str]: List of guessed unit tests commands
    """
    targets: List[str] = []

    readme_path = Path(target, "README.md")
    if readme_path.is_file():
        with open(readme_path, encoding="utf8") as readme_f:
            readme = readme_f.read()
            if "yarn test" in readme:
                targets += ["yarn test"]

    package_path = Path(target, "package.json")
    if package_path.is_file():
        with open(package_path, encoding="utf8") as package_f:
            package = json.load(package_f)
            if "scripts" in package:
                if "test" in package["scripts"]:
                    targets += package["scripts"]["test"]

    return targets
