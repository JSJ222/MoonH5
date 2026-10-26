# Interoperate through a bounded native HDF5 profile

MoonH5 reads and writes actual HDF5 bytes without linking libhdf5. Rather than expose a nominally complete API whose encodings silently fail, it explicitly rejects unsupported storage and datatype variants. Byte-oriented library entry points keep filesystem and network policies with the caller; h5py is an independent development-time oracle, not a runtime dependency.
