"""
Process execution helpers.
"""
import logging
import os
from pathlib import Path
import shutil
import subprocess
from typing import Any, Dict, List, Optional, Union

LOGGER = logging.getLogger("CryticCompile")


def run(
    cmd: List[str],
    cwd: Optional[Union[str, os.PathLike]] = None,
    extra_env: Optional[Dict[str, str]] = None,
    **kwargs: Any,
) -> Optional[subprocess.CompletedProcess]:
    """
    Execute a command in a cross-platform compatible way.

    Args:
        cmd (List[str]): Command to run
        cwd (PathLike): Working directory to run the command in
        extra_env (Dict[str, str]): extra environment variables to define for the execution
        **kwargs: optional arguments passed to `subprocess.run`

    Returns:
        CompletedProcess: If the execution succeeded
        None: if there was a problem executing
    """
    subprocess_cwd = Path(os.getcwd() if cwd is None else cwd).resolve()
    subprocess_env = None if extra_env is None else dict(os.environ, **extra_env)
    subprocess_exe = shutil.which(cmd[0])

    if subprocess_exe is None:
        LOGGER.error("Cannot execute `%s`, is it installed and in PATH?", cmd[0])
        return None

    LOGGER.info(
        "'%s' running (wd: %s)",
        " ".join(cmd),
        subprocess_cwd,
    )

    try:
        return subprocess.run(
            cmd,
            executable=subprocess_exe,
            cwd=subprocess_cwd,
            env=subprocess_env,
            check=True,
            capture_output=True,
            **kwargs,
        )
    except FileNotFoundError:
        LOGGER.error("Could not execute `%s`, is it installed and in PATH?", cmd[0])
    except subprocess.CalledProcessError as e:
        LOGGER.error("'%s' returned non-zero exit code %d", cmd[0], e.returncode)
        stdout, stderr = (
            e.stdout.decode(errors="backslashreplace").strip(),
            e.stderr.decode(errors="backslashreplace").strip(),
        )
        if stdout:
            LOGGER.error("\nstdout: ".join(stdout.split("\n")))
        if stderr:
            LOGGER.error("\nstderr: ".join(stderr.split("\n")))
    except OSError:
        LOGGER.error("OS error executing:", exc_info=True)

    return None
