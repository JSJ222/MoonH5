# Sources and licenses

- MoonH5 HDF5 runtime: original MoonBit implementation under the root MIT license, developed with AI assistance. No pyfive, jsfive, or libhdf5 source was copied into this runtime.
- HDF Group [format specification](https://portal.hdfgroup.org/documentation/hdf5/latest/_f_m_t3.html): consulted for byte encodings and invariants. This project does not redistribute the specification text or claim HDF Group endorsement.
- Bob Jenkins [lookup3](https://www.burtleburtle.net/bob/c/lookup3.c): public-domain algorithm, independently expressed in `checksum.mbt`; used for HDF5 metadata checksums, not for cryptographic authentication.
- [moonbit-community/flate](https://github.com/moonbit-community/flate), version 0.10.0: Apache-2.0 pure MoonBit raw DEFLATE dependency. HDF5 filter framing, bounded decoding policy, shuffle, Fletcher32 and chunk mapping are implemented here. Dependency code is not counted as MoonH5 source.
- [moonbitlang/async](https://github.com/moonbitlang/async), version 0.22.5: Apache-2.0, used only by the native filesystem CLI; MoonBit core is supplied by the toolchain under its own license.
- [h5py](https://github.com/h5py/h5py), version 3.15.1: BSD-3-Clause; [NumPy](https://github.com/numpy/numpy), version 2.4.6: BSD-3-Clause. Installed only into a development test environment. No library source is vendored. All example values and generated `.h5` fixtures are original synthetic data; their generation scripts are in `scripts/`.
- `fixture_data_wbtest.mbt` is mechanically generated test DATA from those original fixtures, not handwritten algorithmic code; effective-source statistics explicitly exclude it.
- `tools/windows` is reused Apache-2.0 build tooling from the user's local MoonSparql project. Its original code and full license are retained there. It is not runtime code or counted MoonBit source.

The MIT license applies to original MoonH5 code and original fixture generation/testing code. The separate licenses above continue to apply to their respective components. Audit/application/AI-assistance reports are intentionally private and excluded from Git and package archives.
