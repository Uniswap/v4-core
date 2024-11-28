import platform
import subprocess
import sys


def mac_can_run_intel_binaries() -> bool:
    """Check if the Mac is Intel or M1 with available Rosetta. Will throw an exception if run on non-macOS."""
    assert sys.platform == "darwin"
    if platform.machine() == "arm64":
        # M1/M2 Mac
        result = subprocess.run(["/usr/bin/pgrep", "-q", "oahd"], capture_output=True, check=False)
        return result.returncode == 0

    # Intel Mac
    return True
