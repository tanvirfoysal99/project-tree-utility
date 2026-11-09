# Architecture

For a source layout, complete public-interface map, build instructions, and the
command-change workflow, see [Developer guide](DEVELOPER_GUIDE.md).

The executable and reusable library share one Cargo package. There is no runtime
dependency on the legacy tree or a shell interpreter.

| Module | Responsibility |
| --- | --- |
| `main` | UTF-8 argument boundary and process exit |
| `cli` | Public parser, legacy aliases/positionals, menu, dispatch, polling watch |
| `formats` | Strict JSON/YAML/text parsing, normalized entry model, rendering, merge |
| `safety` | Portable names, destination checks, bounded reads, atomic writes |
| `scan` | Shared scope configuration, complete directory snapshots, comparisons |
| `operations` | Scaffold preflight/execution and verify/sync mutation |
| `templates` | Embedded application presets and file content lookup |
| `library` | Locked, atomic, versioned saved-layout snapshots |
| `auth` | Native vault adapters and bounded Git credential-helper protocol |
| `remote` | Validated provider URLs, bounded HTTPS requests, tree pagination |

## Entry model

An entry contains a canonical `/`-separated relative path, a directory boolean,
and optional exact content/template strings. Normalization infers missing
directories, rejects case-folded duplicates/type conflicts, canonicalizes ancestor
spelling, and produces deterministic ordering. Filesystem comparison uses native
case matching; layout portability rules remain consistent across platforms.

## Execution boundaries

Parsing and normalization are independent of filesystem mutation. Scans return
complete snapshots or errors. Scaffold validates before writes. Sync compares,
preflights, mutates eligible paths, and scans again. Neither operation offers
whole-project rollback. Watch reuses the scanner without invoking mutation.

Library snapshots embed the saved entries, so authoritative index and content
commit together. Exported text files are regenerable views. Lock ownership is
held by the Library instance and released when its file handle closes.

## Portability

Shared code uses standard paths and filesystem APIs. Windows metadata adapters
recognize reparse points; Windows/macOS keyring dependencies are selected by
target configuration. Unix-like environments use configured Git credential
helpers. TLS uses rustls instead of a system OpenSSL dependency. Native C build
tools are still required when building its cryptographic dependency.

## Dependency policy

Commit `Cargo.lock` for reproducible application dependency selection. Use
`--locked` in tests/builds. Release builds enable thin LTO, one codegen unit, and
symbol stripping. Keep dependency updates deliberate and validate all target
platforms; minimal version declarations do not replace the lockfile. No runtime
plugin loading or self-modifying updater is provided.
