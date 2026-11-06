# Changelog

## 0.2.0 — 2026-11-06

- Add recursive fixed-width compound, array and integer enum datatypes, structured attributes and field/base projection APIs with descriptor isolation and budgets.
- Add standard chunked writing via unpaged fixed-array indexes, zlib/DEFLATE + shuffle + Fletcher32 pipelines, edge padding and explicit compressed repacking.
- Read modern single-chunk and early-allocated implicit indexes; add independent h5py/HDF5 typed roundtrips and format expansion roadmap.

- 无损形状重排。
- 有序轴采样 gather。
- 增加回归测试、独立可运行示例与 CI 示例步骤；详见 docs/EXPANSION_20261106.md。

## 0.1.0 — 2026-11-01

- 多维轴置换：ArrayValue::transpose
- 兼容数组按轴拼接：ArrayValue::concat_axis
- 增加边界回归、可运行集成示例和CI步骤。

### Initial implementation

- Bounded HDF5 superblocks, object headers, legacy and compact group links.
- Fixed atomic datasets, inline attributes, contiguous/compact and legacy/modern unpaged fixed-array chunk reads.
- Gzip, shuffle and Fletcher32 decoding with independent h5py fixtures.
- Hyperslab planning, functional updates, endian exchange, semantic repacking.
- Three application examples, scale workload, native file CLI, all-backend CI configuration.
- Public namespace: JSJ222/moonh5; reproducible compiler/core, Linux/Windows CI and history/package hygiene checks.
