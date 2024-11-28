"""
Module handling the file naming operation (relative -> absolute, etc)
"""

import logging
import os.path
import platform
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Union, Callable, Optional

from crytic_compile.platform.exceptions import InvalidCompilation

# Cycle dependency
if TYPE_CHECKING:
    from crytic_compile import CryticCompile

LOGGER = logging.getLogger("CryticCompile")


@dataclass
class Filename:
    """Path metadata for each file in the compilation unit"""

    def __init__(self, absolute: str, used: str, relative: str, short: str):
        self.absolute = absolute
        self.used = used
        self.relative = relative
        self.short = short

    def __hash__(self) -> int:
        return hash(self.relative)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Filename):
            return NotImplemented
        return self.relative == other.relative

    def __repr__(self) -> str:
        return f"Filename(absolute={self.absolute}, used={self.used}, relative={self.relative}, short={self.short}))"


def extract_name(name: str) -> str:
    """Convert '/path:Contract' to Contract

    Args:
        name (str): name to convert

    Returns:
        str: extracted contract name
    """
    return name[name.rfind(":") + 1 :]


def extract_filename(name: str) -> str:
    """Convert '/path:Contract' to /path

    Args:
        name (str): name to convert

    Returns:
        str: extracted filename
    """
    if not ":" in name:
        return name
    return name[: name.rfind(":")]


def combine_filename_name(filename: str, name: str) -> str:
    """Combine the filename with the contract name

    Args:
        filename (str): filename
        name (str): contract name

    Returns:
        str: Combined names
    """
    return filename + ":" + name


def _verify_filename_existence(filename: Path, cwd: Path) -> Path:
    """
    Check if the filename exist. If it does not, try multiple heuristics to find the right filename:
    - Look for contracts/FILENAME
    - Look for node_modules/FILENAME
    - Look for node_modules/FILENAME in all the parents directories


    Args:
        filename (Path): filename to check
        cwd (Path): directory

    Raises:
        InvalidCompilation: if the filename is not found

    Returns:
        Path: the filename
    """

    if filename.exists():
        return filename

    if cwd.joinpath(Path("contracts"), filename).exists():
        filename = cwd.joinpath("contracts", filename)
    elif cwd.joinpath(filename).exists():
        filename = cwd.joinpath(filename)
    # how node.js loads dependencies from node_modules:
    # https://nodejs.org/api/modules.html#loading-from-node_modules-folders
    elif cwd.joinpath(Path("node_modules"), filename).exists():
        filename = cwd.joinpath("node_modules", filename)
    else:
        for parent in cwd.parents:
            if parent.joinpath(Path("node_modules"), filename).exists():
                filename = parent.joinpath(Path("node_modules"), filename)
                break

    if not filename.exists():
        raise InvalidCompilation(f"Unknown file: {filename}")

    return filename


# pylint: disable=too-many-branches
def convert_filename(
    used_filename: Union[str, Path],
    relative_to_short: Callable[[Path], Path],
    crytic_compile: "CryticCompile",
    working_dir: Optional[Union[str, Path]] = None,
) -> Filename:
    """Convert a filename to CryticCompile Filename object.
    The used_filename can be absolute, relative, or missing node_modules/contracts directory

    Args:
        used_filename (Union[str, Path]): Used filename
        relative_to_short (Callable[[Path], Path]): Callback to translate the relative to short
        crytic_compile (CryticCompile): Associated CryticCompile object
        working_dir (Optional[Union[str, Path]], optional): Working directory. Defaults to None.

    Returns:
        Filename: Filename converted
    """
    filename_txt = used_filename
    if platform.system() == "Windows":
        elements = list(Path(filename_txt).parts)
        if elements[0] == "/" or elements[0] == "\\":
            elements = elements[1:]  # remove '/'
            elements[0] = elements[0] + ":/"  # add :/
        filename = Path(*elements)
    else:
        filename = Path(filename_txt)

    # cwd points to the directory to be used
    if working_dir is None:
        cwd = Path.cwd()
    else:
        working_dir = Path(working_dir)
        if working_dir.is_absolute():
            cwd = working_dir
        else:
            cwd = Path.cwd().joinpath(Path(working_dir)).resolve()

    if crytic_compile.package_name:
        try:
            filename = filename.relative_to(Path(crytic_compile.package_name))
        except ValueError:
            pass

    filename = _verify_filename_existence(filename, cwd)

    absolute = Path(os.path.abspath(filename))

    # This returns original path if *path* and *start* are on different drives (for Windows platform).
    try:
        relative = Path(os.path.relpath(filename, Path.cwd()))
    except ValueError:
        relative = Path(filename)

    # Build the short path
    try:
        if cwd.is_absolute():
            short = absolute.relative_to(cwd)
        else:
            short = relative.relative_to(cwd)
    except ValueError:
        short = relative
    except RuntimeError:
        short = relative

    short = relative_to_short(short)
    # Starting with v0.8.8 (https://github.com/ethereum/solidity/pull/11545), solc normalizes the paths to not include the drive on Windows,
    # so it's important we use posix path here to avoid issues with the path comparison.
    return Filename(
        absolute=absolute.as_posix(),
        relative=relative.as_posix(),
        short=short.as_posix(),
        used=Path(used_filename).as_posix(),
    )
