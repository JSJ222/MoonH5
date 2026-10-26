# HDF5 array interchange

An HDF5 file contains a graph of groups and typed datasets. MoonH5 exchanges a bounded, explicitly documented subset of that graph.

## Language

**Dataset**: A homogeneous collection of fixed-size elements with a dataspace and a datatype.
_Avoid_: Table, document

**Dataspace**: The extent of a dataset or attribute, classified as scalar, simple, or null.
_Avoid_: Buffer length

**Hyperslab**: A regular selection of blocks along each dimension of a simple dataspace.
_Avoid_: Slice when block length is greater than one

**Link**: A named relationship from a group to an object or to another path.
_Avoid_: Child object when discussing aliases

**Attribute**: A small typed value attached to a group or dataset, not a separately linked dataset.
_Avoid_: Column

**Profile**: The exact set of HDF5 encodings MoonH5 accepts or emits; not a claim of full HDF5 conformance.
_Avoid_: Full support
