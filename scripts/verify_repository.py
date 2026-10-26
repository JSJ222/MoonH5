"""Audit tracked source and material exclusion without network or mutations."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
git = ["git", "-c", f"safe.directory={root.as_posix()}"]
tracked = subprocess.check_output(git + ["ls-files", "-z"], cwd=root).decode().split("\0")
counts = dict(library=0, tests=0, examples=0, cli=0)
for name in filter(None, tracked):
    forbidden = {"_local", "_build", ".mooncakes", ".venv", "__pycache__"}
    if forbidden.intersection(Path(name).parts) or any(s in name for s in ("申报书", "审查报告", "辅助报告", "汇总报告")):
        raise SystemExit(f"Private/generated material tracked: {name}")
    if not name.endswith(".mbt") or name == "fixture_data_wbtest.mbt":
        continue  # Generated fixture DATA never counts as effective source.
    category = "tests" if name.endswith("test.mbt") else "examples" if name.startswith("examples/") else "cli" if name.startswith("cmd/") else "library"
    counts[category] += sum(bool(line.strip()) and not line.lstrip().startswith("//") for line in (root / name).read_text(encoding="utf-8").splitlines())
total = sum(counts.values())
commits = int(subprocess.check_output(git + ["rev-list", "--count", "HEAD"], cwd=root))
print({**counts, "effective_moonbit_total": total, "commits": commits, "excluded_generated_fixture_data": True})
if total <= 4000:
    raise SystemExit("Effective MoonBit source must exceed 4000 lines")
if commits <= 30:
    raise SystemExit("Development history must exceed 30 commits (use full git history)")
archives = list((root / "_build" / "publish").glob("*.zip"))
for archive in archives:
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            parts = set(name.replace("\\", "/").split("/"))
            if {"_local", ".git", ".mooncakes", ".venv", "__pycache__"}.intersection(parts):
                raise SystemExit(f"Private/cache directory in package: {name}")
            if any(s in name for s in ("申报书", "审查报告", "辅助报告", "汇总报告")):
                raise SystemExit(f"Private material in package: {name}")
print(f"Publication archives checked without upload: {len(archives)}")
