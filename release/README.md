# Project Tree Utility

**Rust edition · 3.0.0**

**Start here:** [Where to type commands and a first-run walkthrough](docs/GETTING_STARTED.md).
**Complete reference:** [All 12 commands, every option, every format, defaults, and examples](docs/CLI.md).
**Developers:** [Build, architecture, APIs, tests, and contribution workflow](docs/DEVELOPER_GUIDE.md).

A command-line toolkit for describing, exporting, scaffolding, merging, verifying,
and monitoring project directory structures. Built for Windows, Linux, macOS,
and Android through Termux. No PowerShell or Batch backend is required.

This directory is a standalone Cargo project. It does not depend on or modify the
legacy implementation beside it. The Rust edition retains the public command
names and reusable structure formats, with deliberate changes documented in
[Migration](docs/MIGRATION.md).

## Build and run

For the portable Windows package, extract it and run `ptu.exe` directly. Rust
is not required. The source, tests, and scripts are included for inspection or
rebuilding; the Cargo commands below are for source builds.

Install a current stable Rust toolchain and the platform linker/build tools.
From this directory:

```sh
cargo build --release --locked
cargo test --locked
```

The executable is `target/release/ptu.exe` on Windows and `target/release/ptu`
elsewhere. End users of a correctly packaged executable do not need Rust.
Platform packaging and native runtime requirements are covered in
[Installation](docs/INSTALLATION.md).

```sh
# Examples use forward slashes, which also work in Windows paths.
ptu export --ci --root ./my-app --format json --output ./layout.json --max-depth 0
ptu export --ci --root ./my-app --format treesym --output ./tree.txt --max-depth 0
ptu scaffold --ci --structure ./layout.json --target ./projects --project demo --dry-run
ptu scaffold --ci --structure ./layout.json --target ./projects --project demo
ptu verify --ci --live ./projects/demo --structure ./layout.json
```

Replace `ptu` with `./target/release/ptu` or `./target/release/ptu.exe` until
installed on `PATH`. PowerShell also accepts `.\target\release\ptu.exe`.
Run without arguments on a terminal for the interactive command menu, or use
`ptu --help` and `ptu <command> --help`.
Inside the `ptu>` prompt, enter `help` or `--help` for help, a menu number for
a guided operation, or `exit` to close. Do not include `ptu.exe` before commands
entered inside this prompt.

## Capabilities

There are **12 public commands**. Help/version shortcuts and the numbered menu
are additional entry points into these operations, not separate project commands.

| Command | Purpose |
| --- | --- |
| `import` | Validate and convert a structure description |
| `export` | Export a complete local layout snapshot |
| `scaffold` | Create files/directories from a layout or bundled preset |
| `verify` | Compare structure; optionally create missing or delete eligible extras |
| `merge` | Combine layouts with conflict detection or explicit preference |
| `watch` | Report layout changes or drift using periodic snapshots |
| `gittree` | Export GitHub/GitLab repository tree metadata over HTTPS |
| `auth` | Store/clear remote credentials through a supported credential backend |
| `library` | Save, list, export, rename, delete, and purge structures |
| `security` | Validate structure, portable names, and destination containment |
| `detection` | Accept legacy positional analysis/merge commands |
| `version` | Print the local version or query upstream release metadata |

Input formats: dash, tab, space, tree symbols, JSON, YAML. Reusable output:
importable dash, tree symbols (`treesym`), JSON, YAML. Display output: plain text,
Markdown, summary.
Presets: `react-vite`, `hono-worker`, `monorepo-pnpm`.

## Data and safety

Scans include hidden entries and fail on inaccessible or unsupported entries,
symbolic links, and Windows reparse points. Scaffold validates its full plan
before writing. Synchronization is opt-in; deletion additionally requires
`--delete-extras`. Dry-run creates nothing. Library data lives in a per-user
directory or the explicit `PTU_DATA_DIR`, separately from legacy data.

Layout exports contain names and types, **not existing source file contents**.
Mutations are not whole-project transactions: runtime I/O failures can leave
completed changes. Path checks are not a sandbox against another process
concurrently replacing directories. Read [Security](docs/SECURITY.md) and
[Operations](docs/OPERATIONS.md) before using sync on valuable data.

## Documentation

- [Getting started: where to type and what to run](docs/GETTING_STARTED.md)
- [Complete developer/maintainer guide and API reference map](docs/DEVELOPER_GUIDE.md)
- [Installation and platforms](docs/INSTALLATION.md)
- [Command reference](docs/CLI.md)
- [Structure formats](docs/FORMATS.md)
- [Operations and recovery](docs/OPERATIONS.md)
- [Security model](docs/SECURITY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Migration and compatibility](docs/MIGRATION.md)
- [Release procedure](docs/RELEASING.md)
- [Tests and coverage](tests/README.md)
- [Pre-release QA results](docs/QA_REPORT.md)
- [Contributing](CONTRIBUTING.md)
- [Changes](CHANGELOG.md)

Cross-platform source support does not establish tested release support. See
[Validation](docs/VALIDATION.md) for the checks actually performed in this workspace.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md), matching the original project.
Review its terms before using or distributing the software.
