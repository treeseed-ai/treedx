import subprocess
import sys
from pathlib import Path


def test_generated_openapi_metadata_is_fresh() -> None:
    root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [sys.executable, "scripts/check_treedx_generated_types.py"],
        cwd=root,
        check=False,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
