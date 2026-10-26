"""Mechanically encode original h5py files for backend-independent tests.

Generated literals are test data, excluded from effective source counts.
Do not edit their payloads by hand; regenerate with interop.py first.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
names = ("earliest", "v108", "latest", "edge", "unsupported")
lines = ["// Generated test DATA by scripts/embed_fixtures.py; not effective source."]
for name in names:
    data = (root / "fixtures" / f"{name}.h5").read_bytes()
    lines += ["///|", f'fn fixture_{name}() -> Bytes {{']
    for start in range(0, len(data), 1024):
        escaped = "".join(f"\\x{byte:02x}" for byte in data[start:start+1024])
        more = " +" if start + 1024 < len(data) else ""
        lines.append(f'  b"{escaped}"{more}')
    lines.append("}")
(root / "fixture_data_wbtest.mbt").write_text("\n".join(lines) + "\n", encoding="utf-8")
