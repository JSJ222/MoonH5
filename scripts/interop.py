"""Original deterministic h5py fixtures/oracle; no downloaded datasets.

Run generate OUT_DIR, then check MOON_WRITTEN_FILE. MoonBit CLI output is
compared in a later check step; h5py is never a runtime dependency.
"""
from pathlib import Path
import argparse
import h5py
import numpy as np


def generate(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for bound in ("earliest", "v108", "latest"):
        with h5py.File(directory / f"{bound}.h5", "w", libver=bound) as f:
            g = f.create_group("run")
            g.create_dataset("samples", data=np.arange(12, dtype=">i4").reshape(3, 4))
            g.attrs["unit"] = np.bytes_("K")
            f.create_dataset("scalar", data=np.int64(-(2**63)))
            f.create_dataset("labels", data=np.array([b"one", b"two"], dtype="S5"))
            f.create_dataset("empty", shape=(0, 3), dtype="u1")
            f.create_dataset("null", data=h5py.Empty("f8"))
            f.create_dataset("fill", shape=(2, 3), dtype="i2", fillvalue=-7)
            f["same"] = g["samples"]
            f["relative"] = h5py.SoftLink("run/samples")
            if bound != "latest":
                g.create_dataset("chunked", data=np.arange(35, dtype="i2").reshape(5, 7), chunks=(2, 3))
                g.create_dataset("filtered", data=np.arange(35, dtype=">i4").reshape(5, 7), chunks=(2, 3), compression="gzip", shuffle=True, fletcher32=True)
    print("generated 3 original h5py interoperability fixtures")


def check(path):
    with h5py.File(path, "r") as f:
        np.testing.assert_array_equal(f["experiment/samples"][...], np.arange(6).reshape(2, 3) + .5)
        assert f["counter"][()] == -(2**63)
        assert f["counter"].attrs["revision"] == 7
        assert f["experiment"].attrs["unit"] == b"K"
        assert f["alias"].id == f["experiment/samples"].id
        assert f["labels"][1].decode() == "温度"
        assert f["empty"].shape == (0, 2)
        assert f["null"].shape is None
    print("h5py independently read MoonH5 groups, values, aliases, attributes, and empty/null arrays")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "check"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    (generate if args.action == "generate" else check)(args.path)
