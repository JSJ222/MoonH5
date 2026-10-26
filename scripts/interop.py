"""Original deterministic h5py fixtures/oracle; no downloaded datasets.

Run generate OUT_DIR, then check MOON_WRITTEN_FILE. MoonBit CLI output is
compared in a later check step; h5py is never a runtime dependency.
"""
from pathlib import Path
import argparse
import json
import math
import subprocess
import tempfile
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
            g.create_dataset("chunked", data=np.arange(35, dtype="i2").reshape(5, 7), chunks=(2, 3))
            g.create_dataset("filtered", data=np.arange(35, dtype=">i4").reshape(5, 7), chunks=(2, 3), compression="gzip", shuffle=True, fletcher32=True)
    print("generated 3 original h5py interoperability fixtures")
    with h5py.File(directory / "edge.h5", "w", libver="v108", userblock_size=512) as f:
        f.create_dataset("big_endian_float", data=np.array([1.25, -0., np.inf, np.nan], dtype=">f4"))
        f.create_dataset("many_chunks", data=np.arange(19*23, dtype="i4").reshape(19, 23), chunks=(1, 1))
        f.create_dataset("cube", data=np.arange(60, dtype="u2").reshape(3, 4, 5), chunks=(2, 3, 2), compression="gzip", shuffle=True)
        sparse = f.create_dataset("sparse", shape=(5, 7), chunks=(2, 3), dtype="i2", fillvalue=-9)
        sparse[1, 2] = 77
        f.create_dataset("u64", data=np.array([2**64 - 1], dtype=">u8"))
        f.attrs["version"] = np.array([1, 2], dtype="u2")
    with h5py.File(directory / "unsupported.h5", "w", libver="latest") as f:
        f.create_dataset("modern_chunks", data=np.arange(12), chunks=(3,))
        f.create_dataset("extensible", data=np.arange(12), chunks=(3,), maxshape=(None,))
        f.create_dataset("vlen", data="hello", dtype=h5py.string_dtype())
        g = f.create_group("dense")
        for i in range(12):
            g.create_group(str(i))


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


def verify(cli):
    """Run the actual native executable; compare every emitted value with h5py."""
    cli = cli.resolve()

    def run(*args, success=True):
        result = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, encoding="utf-8")
        if success and result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        if not success and result.returncode == 0:
            raise AssertionError("invalid operation unexpectedly succeeded")
        return result.stdout

    def check_array(actual, expected):
        if isinstance(expected, h5py.Empty):
            assert actual["shape"] is None and actual["values"] == []
            return
        expected = np.asarray(expected)
        assert actual["shape"] == list(expected.shape)
        assert len(actual["values"]) == expected.size
        for a, e in zip(actual["values"], expected.reshape(-1)):
            if expected.dtype.kind in "iu":
                assert int(a) == int(e)
            elif expected.dtype.kind == "f":
                if math.isnan(float(e)):
                    assert a == "NaN"
                elif math.isinf(float(e)):
                    assert a == ("-Infinity" if e < 0 else "Infinity")
                else:
                    assert float(a) == float(e)
                    if e == 0:
                        assert math.copysign(1., float(a)) == math.copysign(1., float(e))
            else:
                assert a == bytes(e).decode("utf-8")

    with tempfile.TemporaryDirectory(prefix="moonh5-oracle-") as temp:
        directory = Path(temp)
        generate(directory)
        for name in ("earliest", "v108", "latest", "edge"):
            source = directory / f"{name}.h5"
            inventory = json.loads(run("read", source))
            with h5py.File(source, "r") as f:
                for entry in inventory:
                    obj = f[entry["path"]]
                    if "data" in entry:
                        check_array(entry["data"], obj[()])
                    for attribute in entry["attributes"]:
                        check_array(attribute["value"], obj.attrs[attribute["name"]])
            target = directory / f"{name}-repacked.h5"
            run("repack", source, target)
            with h5py.File(source, "r") as old, h5py.File(target, "r") as new:
                for entry in inventory:
                    if "data" in entry:
                        if old[entry["path"]].shape is None:
                            assert new[entry["path"]].shape is None
                        else:
                            np.testing.assert_array_equal(old[entry["path"]][()], new[entry["path"]][()])
                if name != "edge":
                    assert new["same"].id == new["run/samples"].id
                    assert isinstance(new.get("relative", getlink=True), h5py.SoftLink)
        written = directory / "moon-written.h5"
        run("write-demo", written)
        check(written)
        before = written.read_bytes()
        run("write-demo", written, success=False)
        assert written.read_bytes() == before
        run("read", directory / "unsupported.h5", success=False)
    print("PASS: h5py bidirectional values, repacking, aliases, attributes, errors, and no-overwrite checks")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "check", "verify"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    {"generate": generate, "check": check, "verify": verify}[args.action](args.path)
