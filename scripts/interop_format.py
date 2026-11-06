"""Independent h5py/HDF5 oracle for structured types and compressed writing.
All datasets are original synthetic values, created in temporary directories.
"""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile
import h5py
import numpy as np


def compare_dtype(a, b):
    assert a.itemsize == b.itemsize, (a, b)
    if a.fields:
        assert a.names == b.names, (a, b)
        for name in a.names:
            assert a.fields[name][1] == b.fields[name][1]
            compare_dtype(a.fields[name][0], b.fields[name][0])
    elif a.subdtype:
        assert b.subdtype and a.subdtype[1] == b.subdtype[1]
        compare_dtype(a.subdtype[0], b.subdtype[0])
    else:
        assert a == b, (a, b)
        assert h5py.check_enum_dtype(a) == h5py.check_enum_dtype(b)


def compare_values(a, b):
    if a.dtype.fields:
        for name in a.dtype.names:
            compare_values(a[name], b[name])
    else:
        np.testing.assert_array_equal(a, b)


def generate(directory):
    state = h5py.enum_dtype({'OFF': 0, 'ON': 1}, basetype='u1')
    dtype = np.dtype({'names': ['id', 'pair', 'state'], 'formats': ['>u8', ('<f4', (2,)), state], 'offsets': [0, 8, 16], 'itemsize': 24})
    records = np.zeros((3, 5), dtype=dtype)
    records['id'] = np.uint64(2**64-1) - np.arange(15, dtype='u8').reshape(3, 5)
    records['pair'][..., 0] = np.arange(15).reshape(3, 5)
    records['pair'][..., 1] = -np.arange(15).reshape(3, 5)
    records['state'] = np.arange(15).reshape(3, 5) % 2
    for bound in ['earliest', 'v108', 'latest']:
        path = directory / (bound + '.h5')
        with h5py.File(path, 'w', libver=bound) as f:
            for name, options in [('contiguous', {}), ('chunked', {'chunks': (2, 3)}), ('compressed', {'chunks': (2, 3), 'compression': 'gzip', 'shuffle': True, 'fletcher32': True})]:
                d = f.create_dataset(name, data=records, **options)
                d.attrs['sample'] = records[0, 0]
            f.create_dataset('state', data=records['state'], dtype=state)
            nested = np.zeros((2,), dtype=[('record', dtype), ('count', '>i8')])
            nested['record'] = records.reshape(-1)[:2]
            nested['count'] = [-(2**63), 2**63-1]
            f.create_dataset('nested', data=nested)
            f.create_dataset('complex', data=np.array([1+2j, -3+4j], dtype='complex128'))
            d = f.create_dataset('array_type', shape=(4,), dtype=np.dtype(('>i2', (2, 3))))
            d[...] = np.arange(24, dtype='i2').reshape(4, 2, 3)
            if bound == 'latest':
                modern = f.create_group('modern')
                modern.create_dataset('single', data=records, chunks=records.shape)
                modern.create_dataset('single_filtered', data=records, chunks=records.shape, compression='gzip', shuffle=True, fletcher32=True)
                # An early allocated, fixed extent, unfiltered modern implicit index.
                dcpl = h5py.h5p.create(h5py.h5p.DATASET_CREATE)
                dcpl.set_chunk((2, 3)); dcpl.set_alloc_time(h5py.h5d.ALLOC_TIME_EARLY)
                space = h5py.h5s.create_simple((4, 6))
                d = h5py.h5d.create(modern.id, b'implicit', h5py.h5t.STD_I32LE, space, dcpl=dcpl)
                d.write(h5py.h5s.ALL, h5py.h5s.ALL, np.arange(24, dtype='<i4').reshape(4, 6))


def verify(cli):
    cli = cli.resolve()
    def run(*args, success=True):
        p = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, encoding='utf8')
        assert (p.returncode == 0) == success, p.stdout + p.stderr
        return p.stdout
    with tempfile.TemporaryDirectory(prefix='moonh5-format-') as temp:
        root = Path(temp)
        generate(root)
        for name in ['earliest', 'v108', 'latest']:
            source = root / (name + '.h5')
            inventory = json.loads(run('read', source))
            with h5py.File(source, 'r') as f:
                for entry in inventory:
                    if 'data' not in entry: continue
                    actual = entry['data']
                    d = f[entry['path']]
                    if actual['type'] in ['compound', 'array', 'enum']:
                        raw = bytes(x for row in actual['values'] for x in row)
                        decoded = np.frombuffer(raw, dtype=d.dtype).reshape(d[()].shape)
                        compare_values(decoded, d[()])
                    else:
                        np.testing.assert_array_equal(np.array(actual['values'], dtype=d.dtype).reshape(d.shape), d[()])
            for command in ['repack', 'repack-compressed']:
                target = root / f'{name}-{command}.h5'
                run(command, source, target)
                with h5py.File(source, 'r') as original, h5py.File(target, 'r') as actual:
                    keys = []
                    original.visititems(lambda key, obj: keys.append(key) if isinstance(obj, h5py.Dataset) else None)
                    for key in keys:
                        a, b = original[key], actual[key]
                        assert a.shape == b.shape
                        compare_dtype(a.dtype, b.dtype)
                        compare_values(a[()], b[()])
                        for attribute in a.attrs:
                            compare_values(np.asarray(a.attrs[attribute]), np.asarray(b.attrs[attribute]))
                        if command == 'repack-compressed':
                            assert b.chunks is not None and b.compression == 'gzip' and b.shuffle and b.fletcher32
                run(command, source, target, success=False)
        target = root / 'native.h5'
        run('write-format', target)
        with h5py.File(target, 'r') as f:
            d = f['records']
            assert d.chunks == (2, 3) and d.compression == 'gzip' and d.shuffle and d.fletcher32
            assert d['id'][0, 0] == 2**64-1 and d['id'][2, 4] == 2**64-15
            np.testing.assert_array_equal(d['pair'][..., 0], np.arange(15).reshape(3, 5))
            assert h5py.check_enum_dtype(d.dtype.fields['state'][0]) == {'OFF': 0, 'ON': 1}
            assert d.attrs['sample']['id'] == 2**64-1
            np.testing.assert_array_equal(f['dense'][()], np.full((32, 32), 7))
            assert f['dense'].id.get_storage_size() < f['dense'].size * f['dense'].dtype.itemsize
            np.testing.assert_array_equal(f['many_chunks'][()], np.arange(1155).reshape(33, 35))
            for level in [0, 1, 9]:
                d = f[f'levels/gzip{level}']
                assert d.compression_opts == level and d.fletcher32
                np.testing.assert_array_equal(d[()], np.array([1, 2, 3, 4, 5, 6, 2**64-1], dtype='u8'))
        run('write-format', target, success=False)
    print('PASS: h5py/HDF5 structured compound/array/enum/complex records, attributes, earliest/v108/latest files, single/implicit indexes, compressed writes and repacking (gzip/shuffle/Fletcher32), exact Uint64 and edge chunks')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('cli', type=Path)
    args = parser.parse_args()
    verify(args.cli)
