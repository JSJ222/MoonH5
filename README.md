# MoonH5

Work in progress: pure MoonBit HDF5 array interchange. The module is intentionally private with a temporary local namespace until the owner selects publication accounts.

The initial profile targets groups, fixed-size atomic datatypes, attributes, scalar/simple/null dataspaces, compact/contiguous datasets, and bounded hyperslab reads. Unsupported encodings are errors, not guessed data. Compatibility and runnable examples will be documented as implementation is verified.

Runtime dependency: MoonBit >= 0.10.16. License: MIT. No libhdf5 runtime binding.

Development: `moon check`, `moon build`, `moon test`.

Application/proposal material and local audit reports are intentionally excluded from Git and package archives.
