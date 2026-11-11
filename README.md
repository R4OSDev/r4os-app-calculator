# CALC.R4X

`CALC.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.7`
- Image target: `/R4OS/SOFTWARE/DESKTOP/CALC.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.

Calculator declares `runtime.parallel=owned-v1` (0.1.4). Its mutable state
belongs to its main thread; the hosted GUI uses the kernel's per-instance
event/frame owners. Background instances can run on different CPUs.

API migration 0.90.68
---------------------
Calculator uses normal App2/Query2 with SDK201/Contract93. The shared Window
owns event waiting and paint publication. Font changes rebuild layout.
Focus loss and input reset clear an armed digit/button before mouse release.
Existing fixed-point arithmetic and display formatting are used by the GUI.
