# Developer and maintainer guide

This guide is for developers building, extending, testing, and distributing the
Rust edition. The end-user interface is documented separately in
[Complete CLI reference](CLI.md); do not infer available flags from module names.

## Source layout and build products

This directory is a standalone Cargo package. In the original repository it is
the `release/` subtree; the legacy files outside it are independent.

```text
Cargo.toml / Cargo.lock       Package, dependencies, compiler/lint/release settings
src/main.rs                  Native executable entry point
src/lib.rs                   Library module exports
src/cli.rs                   Parser, validation, dispatch, guided menu, watch loop
src/formats.rs               Entry model, parsers, normalization, rendering, merge
src/safety.rs                Portable paths, bounded reads, atomic writes
src/scan.rs                  Scope configuration, snapshots, comparison
src/operations.rs            Scaffold and verify/sync mutation
src/templates.rs             Embedded application presets/stubs
src/library.rs               Saved-layout snapshot and exclusive locking
src/auth.rs                  Native vault and Git credential-helper adapters
src/remote.rs                HTTPS transport, provider APIs, release lookup
docs/                        User reference, operations, architecture, QA, release guides
examples/                    Reusable layouts and verification configuration
tests/                       Regression, command, transport, integration, and docs checks
scripts/                     Installation and packaging scripts
.github/workflows/ci.yml      Standalone-repository CI template
target/                      Local build/test/cache output; not shipped as source data
dist/                        Locally produced archives and checksums
```

Package name: `project-tree-utility`. Rust library import: `project_tree_utility`.
Executable name: `ptu` (`ptu.exe` on Windows). Edition: 2024. Manifest minimum
Rust version: 1.88; recorded QA uses the toolchain in [Validation](VALIDATION.md).
Application code forbids unsafe Rust. This does not make third-party dependencies
or native APIs part of that lint guarantee.

## Build and run

From this directory with Rust and the platform linker/C toolchain available:

```sh
cargo build --locked
cargo run --locked -- --help
cargo run --locked -- export --root ./src --format treesym --output ./source-tree.txt --max-depth 0
cargo build --release --locked
cargo doc --locked --no-deps
```

The `--` after `cargo run` separates Cargo options from PTU arguments. Output is
in `target/debug/` or `target/release/`; generated API documentation is under
`target/doc/`. A release executable is optimized with thin LTO, one codegen unit,
and symbol stripping. End users of a correctly packaged executable do not need Rust.

Windows source builds need an appropriate MSVC toolchain/C++ Build Tools or GNU
toolchain/MinGW-w64. Unix builds need their native toolchain, and TLS's native
cryptographic dependency requires a C compiler during compilation. Runtime HTTP
uses rustls rather than a system OpenSSL dependency.

To install a developer build through Cargo:

```sh
cargo install --path . --locked
```

That installs the `ptu` binary through Cargo's installation mechanism and needs
its bin directory on PATH. It is separate from the portable end-user installer.
See [Installation](INSTALLATION.md) for source/portable/platform prerequisites.

## Platform adapter boundaries

| Environment | Build/runtime boundary |
| --- | --- |
| Windows | Windows reparse-point metadata and native Credential Manager adapter; publish an OS/architecture-specific executable |
| Linux | Unix filesystem behavior and configured Git credential helpers; choose a compatible runtime/libc baseline |
| macOS | Unix filesystem behavior and native Keychain; separate Apple Silicon/Intel artifacts when distributing both |
| Android/Termux | Android/Termux-compatible executable/toolchain and Git helper availability; not an ordinary Linux ARM64 binary |

Example target identifiers include `x86_64-pc-windows-msvc`,
`x86_64-pc-windows-gnu`, `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`,
`aarch64-apple-darwin`, `x86_64-apple-darwin`, and `aarch64-linux-android`.
Listing a target is not a tested-release claim. Adding a Rust target alone does
not supply an Android NDK/linker, foreign system libraries, or a runtime test
environment. Prefer native builds for the provided host-detecting packaging
scripts. Do not label cross-built output using the host packager without checking
architecture and native dependencies. iOS is outside scope.

## Request lifecycle

1. `main` rejects non-UTF-8 process arguments and calls `cli::entrypoint`.
2. `Options::parse` handles command names, global CI/help, aliases, named values,
   switches, and fixed positional slots.
3. Help is handled without performing an operation. Otherwise `Options::validate`
   checks required fields, allowed values, action-specific requirements, and
   incompatible combinations before dispatch.
4. File descriptions are parsed and normalized; scans return complete snapshots
   or fail. Backend operations consume validated models rather than shell code.
5. Mutations preflight, recheck destinations at use, apply eligible operations,
   and report errors. Verify/sync performs a fresh final scan.
6. The CLI translates results into documented exit codes. Library instances and
   other owned resources leave scope before the process exit.

Interactive text first goes through `parse_interactive`, which strips Windows/
Unix console line endings and tokenizes shell-like quoting. Numbered prompts
construct the same parser arguments. There is no shell command execution inside
the interactive command menu.

## Public model contracts

### Entry

`formats::Entry` contains `path: String`, `is_dir: bool`, optional `content`,
and optional `template`. Serialized directory indicator is `isDir`. Missing and
empty content are different: `None` permits a stub; `Some("")` is explicit empty
content. A path is root-relative, canonicalized to `/` separators.

Call `formats::normalize` after constructing entries programmatically. It
validates portable names and metadata, infers directories, rejects duplicate
case-folded paths and type conflicts, canonicalizes ancestor spelling, and returns
deterministic ordering. Do not pass arbitrary unnormalized entries to rendering,
comparison, or mutation code and assume validation will be repeated identically.

Portable duplicate rejection applies across platforms. Filesystem comparison is
case-insensitive on Windows and exact on Unix in this implementation. This is
an explicit policy, not automatic detection of a particular volume's case behavior.

### Scope and comparison

`scan::Scope` holds exclusion rules, maximum depth, and export display mode.
Depth counts components below the root. Defaults are visible in `scan.rs` and
the CLI reference. `Comparison` contains missing/extra entries, conflicting paths,
and a matched count. A clean comparison means structural agreement, not equal bytes.

`operations::Counts` records created, overwritten, skipped, and deleted counts.
Do not treat counts or a partial operation as a transactional rollback record.

### Library snapshot

`library::Saved` stores ID, name, source label, and normalized entries. The
private versioned index is the authoritative snapshot. Derived `tree-<id>.txt`
files can be regenerated. Mutations build a candidate index, commit it, then
adopt it in memory; a failed pre-commit write must not change the live in-memory
view. Lock ownership is held by the Library instance.

## API reference map

These are current source-level interfaces, not an independently published stable
plugin API. The CLI is the primary application contract. Use generated Rust docs
and the source for exact signatures, types, ownership, and error context.

### cli

| Interface | Contract |
| --- | --- |
| `HELP` | General command overview printed for top-level help |
| `Options::parse` | Parse token strings; does not read structure files or run commands |
| `Options::get`, `required`, `value` | Optional, required, or defaulted string lookup |
| `Options::flag`, `number` | Switch presence and checked nonnegative numeric lookup |
| `Options::validate` | Validate command/action fields and allowed value combinations |
| `parse_interactive` | Convert one console line into Options after line-ending cleanup |
| `run` | Execute parsed options and return a result/exit status; use parsed valid command names |
| `entrypoint` | Select menu/noninteractive behavior, report errors, return process status |

### formats

| Interface | Contract |
| --- | --- |
| `Entry::new`, `Entry::depth` | Construct a record; count path components |
| `detect` | Detect a supported input representation; fail on ambiguity |
| `read` | Bounded UTF-8 file read, optional detection, parse and normalize |
| `parse` | Parse explicit text/format/space width and normalize |
| `normalize` | Establish entry/path/hierarchy invariants |
| `render` | Produce one supported representation from a valid layout |
| `merge` | Apply union or explicit preference to two normalized descriptions |

### safety

| Interface | Contract |
| --- | --- |
| `MAX_INPUT_BYTES`, `MAX_ENTRIES`, `MAX_DEPTH` | Shared defensive size/complexity bounds |
| `relative_path` | Validate portable root-relative layout paths and normalize separators |
| `absolute` | Resolve lexical absolute paths; reject ambiguous drive-relative forms |
| `is_link` | Recognize symlinks and Windows reparse points from metadata |
| `check_ancestors` | Reject links/reparse points in existing ancestors |
| `destination` | Validate one layout path under a base and inspect ancestors |
| `contained` | Check a candidate against an absolute base and ancestor policy |
| `read_text` | Read a regular UTF-8 input within the size bound; optional BOM accepted |
| `atomic_write` | Stage beside a destination, flush, replace atomically; parent must exist |
| `ensure_regular` | Require a regular file and acceptable ancestors |

These checks are not race-safe handle-relative sandboxing. Another process with
write access can change the filesystem between checks and use. Atomic replacement
of one file is not an all-or-nothing multi-entry project transaction.

### scan

| Interface | Contract |
| --- | --- |
| `DEFAULT_EXCLUDES`, `Scope::default` | Baseline scope settings |
| `Scope::load` | Load one selected local config plus supported simple gitignore rules |
| `Scope::includes` | Apply shared exclusion/depth rules to a relative path |
| `Scope::add_excludes`, `Scope::validate` | Extend literal rules; validate display mode |
| `scan` | Complete deterministic snapshot or error; never a silently successful partial snapshot |
| `displayed` | Apply export kind filtering, retaining ancestors where the output needs them |
| `compare` | Compare in-scope expected entries with an actual snapshot |
| `Comparison::clean`, `print` | Test/report structural differences |

### operations and templates

| Interface | Contract |
| --- | --- |
| `operations::scaffold` | Preflight and execute a normalized layout with overwrite/dry-run policy |
| `operations::verify` | Scan/compare, optionally synchronize/delete, rescan, return report/counts |
| `templates::preset` | Return a normalized embedded preset; unknown names fail |
| `templates::stub` | Resolve a matching preset file or empty stub; explicit entry content is handled by operations |

### library

| Interface | Contract |
| --- | --- |
| `data_dir` | Per-user library location or explicit PTU_DATA_DIR |
| `Library::open` | Validate/load snapshot while holding an exclusive lock |
| `list`, `find` | Read records; consistent Unicode lowercase names and numeric ID lookup |
| `save` | Normalize input, choose unique name/ID, commit a new record |
| `export` | Materialize reusable dash and return its path, or no matching record |
| `rename` | Refuse conflicting/invalid names and commit a rename |
| `delete`, `purge` | Commit removal of records and remove managed derived views |

### auth

| Interface | Contract |
| --- | --- |
| `target` | Canonical HTTPS credential URL without user info/query/fragment |
| `store` | Validate token and persist via the selected platform backend |
| `clear` | Remove a target credential through the selected backend |
| `lookup` | Try repository/host contexts with native vault and Git-helper lookup |

Secrets must not be included in literal CLI arguments, normal logs, snapshots,
or error context. Native identities belong to this Rust edition. On Linux/Termux,
configured Git helpers are trusted external programs, not proof of secure storage.

### remote

| Interface | Contract |
| --- | --- |
| `HttpFailure` | Typed HTTP status failure used to distinguish cases such as no published release |
| `Repository`, `repository` | Validated provider URL, repository identity, and API base |
| `client` | Production HTTPS-only client with TLS, redirect, and timeout policy |
| `request` | Bounded request/retry/response parsing with sensitive authorization headers |
| `fetch` | Provider tree retrieval with supported credential lookup |
| `fetch_anonymous` | Provider tree retrieval without vault/helper access |
| `fetch_with` | Provider algorithm with supplied transport for deterministic fixtures |
| `push_node` | Validate/filter a remote node into the entry model |
| `check_version` | Query fixed upstream release endpoint |
| `check_version_with` | Release-result behavior with supplied transport for fixtures |

Tests can supply fixture transports and loopback-only clients. Do not add a
hidden production TLS bypass or arbitrary insecure endpoint switch to make tests
pass. A failed/truncated response must never become a successful empty layout.

## Example: use the library from Rust

Inside a binary/example that depends on this crate and anyhow:

```rust
use anyhow::Result;
use project_tree_utility::{formats, safety};
use std::path::Path;

fn main() -> Result<()> {
    let entries = formats::read(Path::new("layout.yaml"), None, 2)?;
    let tree = formats::render(&entries, "treesym")?;
    safety::atomic_write(Path::new("tree.txt"), tree.as_bytes())?;
    Ok(())
}
```

The output parent must exist. This converts a description; call `scan::scan`
with an appropriate Scope when the source is a live directory instead.

## Adding or changing a command/option

1. Add/update its canonical key and positional mapping in `specification`.
2. Add any intentional compatibility alias; do not silently reinterpret an existing
   positional slot to fill an omitted named option.
3. Validate required fields, enum values, ranges, and incompatible combinations
   before opening stores, network connections, or output files.
4. Implement dispatch/backend behavior with the shared entry/path/scope rules.
5. Update the matching command table in CLI.md, the option index, formats/action
   lists, and relevant getting-started examples. A flag name without its meaning,
   default, valid values, and applicable command is incomplete documentation.
6. Keep guided prompts and command help aligned. Add a regression that demonstrates
   the original failure or the new behavior through the public command where useful.
7. Run the documentation coverage checker and the required code checks. Review
   platform-specific adapters on their actual platforms before changing support claims.
8. Update changelog, QA/validation records, and packaging when behavior changes.

## Required checks

```powershell
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
.\tests\docs-reference.ps1
cargo build --release --locked
```

Default tests use disposable trees under `target/test-fixtures`, dummy inputs,
and local transport fixtures. They do not access public repositories or native
vault records. Opt-in integration:

```powershell
cargo test --locked --test native_auth -- --ignored
.\tests\live-commands.ps1
.\tests\template-builds.ps1
```

Native auth creates and removes a unique dummy record. Live checks depend on
provider availability/quotas; use anonymous public repositories. Template checks
download dependencies into disposable projects with a local cache and do not
deploy. Retained QA fixtures are ignored under `target/` and can be inspected.
See [Tests](../tests/README.md) for suite coverage, packaged-binary overrides,
cleanup expectations, and opt-in behavior.

## Packaging and publication

```powershell
.\scripts\package.ps1
.\tests\package-check.ps1 -IncludeNativeAuth
```

On a native matching Linux/macOS/Termux host, use `sh scripts/package.sh`.
Archives contain the executable, complete docs, sources, tests, examples, scripts,
manifest/lockfile, and license, excluding build caches/toolchains. Check native
dependencies and verify all packaged local links and example paths. A single
executable does not imply compatibility with every OS/architecture.

Publishing/registration is separate work. Packaging does not create a Homebrew,
WinGet, Ubuntu, or official Termux package. GitHub does not execute the CI template
while it is nested under `release/` in the original repository; it is a template
for a standalone project root. Use [Releasing](RELEASING.md) for tag/asset naming,
checksums, signing/native gates, and actual publication steps.

## Dependency and reference policy

The direct dependencies and enabled feature choices are defined in
[Cargo.toml](../Cargo.toml); exact resolved versions are in Cargo.lock.

| Direct dependency | Manifest requirement / relevant features | Role |
| --- | --- | --- |
| `anyhow` | `1` | Error propagation and context |
| `base64` | `0.22` | Exact UTF-8 seed-content directives |
| `ctrlc` | `3.4` | Watch shutdown signal handling |
| `directories` | `6` | Per-user library locations |
| `fs2` | `0.4` | Exclusive library file locking |
| `reqwest` | `0.12`; blocking/json/rustls-tls; default features disabled | HTTPS API transport |
| `rpassword` | `7` | Masked interactive token input |
| `serde` | `1`; derive | Data model/snapshot serialization |
| `serde_json` | `1` | JSON structure/API/snapshot data |
| `shell-words` | `1` | Interactive command-line tokenization |
| `url` | `2` | URL component handling |
| `tempfile` | `3` | Staged atomic outputs and disposable test files |
| `yaml-rust2` | `0.10` | YAML parsing with additional schema restrictions |
| `keyring` | `3`; windows-native on Windows, apple-native on macOS | Native credential adapters on those targets |

The project does not use a third-party CLI parsing framework: `cli.rs` implements
the public parser. Linux/Termux credentials use the configured Git helper path,
not a keyring feature silently enabled by this manifest. Transitive dependencies
are not additional public CLI features.

Commit Cargo.lock and use `--locked` in reproducible application checks. Do not
update dependency versions merely to make an uninvestigated test pass. Prefer
maintained libraries and source-specific primary documentation. Review all
affected targets when updating platform/TLS/credential dependencies.

Useful primary references:

- [Rust language book](https://doc.rust-lang.org/book/)
- [Cargo manifest reference](https://doc.rust-lang.org/cargo/reference/manifest.html)
- [Rust target/platform support](https://doc.rust-lang.org/rustc/platform-support.html)
- [reqwest 0.12 documentation](https://docs.rs/reqwest/0.12.28/reqwest/)
- [keyring 3 documentation](https://docs.rs/keyring/3.6.3/keyring/)
- [yaml-rust2 0.10 documentation](https://docs.rs/yaml-rust2/0.10.4/yaml_rust2/)
- [GitHub Git trees REST API](https://docs.github.com/en/rest/git/trees)
- [GitLab repositories API](https://docs.gitlab.com/api/repositories/)

Use the versions selected by the lockfile rather than assuming the newest major
API matches this source. Repository-specific behavior and recorded evidence live
in [CLI](CLI.md), [Formats](FORMATS.md), [Architecture](ARCHITECTURE.md),
[Operations](OPERATIONS.md), [Security](SECURITY.md), and [QA](QA_REPORT.md).
