# HDF5 format expansion and compatibility roadmap

MoonH5 0.2.0, 2026-11-06. These APIs extend the earlier `0.1.0` baseline.
Format coverage is an incremental compatibility programme, not a claim that a
finite initial profile is the final project deliverable. New encodings need
working read/write paths, independent HDF5 files and failure/budget tests.

## Implemented additions

| Area | Current implementation | Practical use |
|---|---|---|
| Compound types | nested fixed-width records, named fields, explicit byte offsets and item size; read versions 1/2/3 layouts, write v3 | instrument records, mixed metadata/value tables, simulation particles |
| Array datatypes | fixed array per element, nested in compound or standalone; read v2/v3, write v3 | vectors, covariance blocks, multichannel samples |
| Enumerated types | integer base with named raw values; read v1/v2/v3 layouts, write v3 | quality flags, categorical scientific metadata |
| Complex values | conventional two-floating-member compound representation (e.g. h5py complex128) | frequency-domain and simulation records |
| Modern storage | read single-chunk (including filtered) and early-allocated implicit indexes, in addition to existing v1 B-tree/unpaged fixed array | common fixed-extent HDF5 producer files |
| Chunk writing | fixed-extent, positive Simple datasets using standard layout v4/unpaged fixed-array indexes | bounded blocked output and interoperability |
| Filter writing | gzip filter's zlib/DEFLATE, shuffle, Fletcher32; composable pipeline | compressed exchange and integrity checking |
| Compressed repacking | opt-in storage choice on existing Document datasets, plus CLI repack-compressed | convert supported input datasets to compressed output |

Primary reference: [HDF Group file format specification](https://support.hdfgroup.org/documentation/hdf5/latest/_f_m_t3.html).
No HDF5 C/Java runtime is bound by the MoonBit core. HDF5/h5py only provide an
independent development oracle; original synthetic datasets are temporary.

## Structured element API

`DataType::Compound(item_size, fields)` uses `CompoundMember{name, offset,
datatype}`. Fields may contain compounds, `ArrayType(dimensions, base)` and
`EnumType(integer_base, [(name, raw_value_bytes), ...])`. Raw values use the
declared base byte order, preserving full UInt64 and Int64 ranges. Unknown enum
values remain representable; `enum_name_at` returns None when there is no label.

`ArrayValue::field(name)` projects one member into an independent typed array,
retaining the dataset dataspace. `expand_array()` appends element array dimensions
after dataset dimensions, without converting bytes. `enum_base()` exposes the
integer values and `element(index)` returns an exact scalar record. Structured
types work in fixed-size attributes and selected array IO as well as datasets.
For whole-record byte-order conversion the existing helper rejects structured
types explicitly; project fields or provide correctly typed raw bytes instead
of assuming that all fields share one endianness.

Type descriptors are defensively copied into ArrayValue and out of datatype().
Validation rejects duplicate names/enum values, overlapping or out-of-range
members, invalid integer bases/dimensions, malformed names, truncated descriptors,
cycles, excessive recursion and arithmetic overflow. Current descriptor limits:
32 nesting levels, 4096 expanded nodes, 256 members per compound/enum, 32 array
axes and 255 UTF-8 bytes per member name. Record padding bytes are retained by
MoonH5; independent semantic comparison does not assume that a third-party
compound conversion initializes padding bytes identically.

Version-1 compound fields using its deprecated inline-array representation are
still rejected; separately encoded standard array members are supported. Native
HDF5 class-11/format-v5 complex datatypes are not implemented; legacy r/i compound
complex values must not be presented as coverage of that newer class.

## Chunk and filter writing

```moonbit
doc.add_dataset("/samples", value,
  chunked=Some(@h5.ChunkOptions::new([16, 16],
    gzip=Some(6), shuffle=true, fletcher32=true)))
```

Use `Document::set_chunking(real_dataset_path, Some(options))` when converting an
existing document; None chooses contiguous output. This validates before changing
state and switches off compact storage. Chunk options are copied. Compact and
chunked arguments are mutually exclusive. Shape rank must match a positive fixed
Simple extent; chunk dimensions must fit it. Scalar/Null/empty and resizable
chunked output remain outside this writer profile and can use existing contiguous
or compact output as appropriate. Gzip levels 0..9 are accepted.

Edge chunks are physically full-sized, with out-of-extent bytes zero-padded.
Data is shuffled, optionally zlib-compressed, then Fletcher32-protected. The
writer applies selected filters to every chunk (filter mask zero); readers still
honour masks in external files. Metadata includes the standard filter pipeline,
layout-v4 fixed-array header/data block, checksums, stored sizes and addresses.
Unpaged indexes use page-bits=30 under the existing count/metadata budgets.

The two-pass file layout remains deterministic. Input arrays, prepared compressed
chunks and the final output can coexist in memory; this is not a disk streaming
writer, an in-place update API or a process peak-memory guarantee. Encoded chunk
bytes, index metadata, file size and chunk count are bounded before final output.
Compression may expand incompressible input. The independent test checks actual
storage reduction on one repetitive dataset; no universal ratio is promised.

## Reproduction and independent evidence

```sh
moon run examples/structured_exchange --target native --deny-warn
moon build --target native --deny-warn
python scripts/interop_format.py _build/native/debug/build/cmd/main/main.exe
python scripts/interop.py verify _build/native/debug/build/cmd/main/main.exe
moon run cmd/main --target native -- write-format NEW.h5
moon run cmd/main --target native -- repack-compressed INPUT.h5 NEW.h5
```

Use the pinned `scripts/requirements-interop.txt` development environment; on
Windows use the README's compiler wrapper and `_local/venv/Scripts/python.exe`.
`interop_format.py` generates earliest/v108/latest-bound files with nested records,
arrays, enum values, compound complex numbers, structured attributes and edge
chunks. It compares typed values, field names/offsets, element size, array shape
and enum mappings after regular and compressed repacking through MoonH5.
Single and implicit chunk indexes are exercised independently. It also consumes
a MoonBit-created file, checks filters and shapes, exact UInt64 extrema, 1155
chunks, gzip levels 0/1/9 and storage reduction on repeated data. Outputs refuse
existing paths. Existing atomic/link/fill/selection interoperability remains a
separate regression. `latest` means the bound selected by the installed HDF5
oracle, not a certification of every future HDF5 format.

CLI structured values are exported as raw element-byte arrays; use the typed
field/array/enum APIs for interpretation. Normal `repack` remains a semantic
rebuild and does not retain original compression/layout. `repack-compressed`
explicitly selects gzip6+shuffle+Fletcher32 and bounded chunk dimensions for
supported positive Simple datasets; it does not preserve every creation property.

## Complexity and next core milestones

Descriptor validation is O(expanded nodes + sum(members²)) under fixed limits;
recursive encode/decode may revisit descriptor subtrees, bounded by depth 32.
Field projection is O(records*field_width), with independent output allocation;
array expansion shares immutable bytes. Chunk assembly is O(padded elements*rank
+ bytes), plus compression work; metadata is O(chunk count). The current builder
retains all encoded chunks. Selection caches only hit chunks but input remains
an in-memory file; indexes are traversed under budgets.

1. **Index expansion**: paged fixed arrays, extensible arrays and v2 B-tree indexes,
   preserving sparse allocation and edge masks. Completion gate: independent
   larger/unlimited-extent files, sparse/fill cases, selection equivalence,
   metadata corruption and traversal limits.
2. **Variable-size metadata/data**: VLEN strings/sequences, global-heap ownership,
   references and dense groups/attributes. Completion gate: producer files with
   empty/null/multilingual values and shared objects; explicit total expansion,
   depth and heap-reference budgets; bidirectional HDF5 validation.
3. **Further type/filter coverage**: opaque/bitfield and native complex class,
   then independently verified additional standard codecs/encodings. Completion
   gate: preservation of type metadata and values, raw fixtures, parameter/mask
   failures and bounded allocation before claiming support.

These are core compatibility milestones, not already-implemented features.
MATLAB v7.3, NetCDF-4 and model formats still require their own higher-level
conventions and complete producer fixtures before compatibility claims.
