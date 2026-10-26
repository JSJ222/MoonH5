# Windows path adapter

The three files in this directory are reused from the user's local MoonSparql project, whose root license is Apache-2.0. The complete upstream license is retained alongside them. They normalize compiler child-process DOS path prefixes for Moon 20261016 on Windows; they are tooling, not HDF5 runtime code and are excluded from MoonBit effective source counts. The scripts modify only process environment variables and generated `_build` files.
