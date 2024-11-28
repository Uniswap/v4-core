"""
.. include:: ../README.md
"""
from .crytic_compile import CryticCompile, compile_all, is_supported
from .compilation_unit import CompilationUnit
from .cryticparser import cryticparser
from .platform import InvalidCompilation
from .utils.zip import save_to_zip
