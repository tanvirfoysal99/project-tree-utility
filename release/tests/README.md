# Tests

Run from the Rust project directory:

```sh
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
cargo fmt --all -- --check
```

Tests use isolated GUID/random-named trees under `target/test-fixtures`. This
keeps artifacts inside this project and avoids platform temporary-directory
symlink aliases. `tempfile` removes each completed fixture. Forced termination
can leave a fixture, which may be inspected and removed manually. Windows
junction tests explicitly remove the junction before fixture cleanup.

| Suite | Coverage |
| --- | --- |
| `formats.rs` | Six input formats, tree-symbol connectors and round-trips, exact content, strict schema, YAML restrictions, malformed indentation, portable names, limits, merge conflicts/preferences |
| `filesystem.rs` | Dry-run, scaffold preflight/overwrite, scan scope, hidden files, sync semantics, conservative deletion, containment, atomic output, Unix symlinks/Windows junctions |
| `cli.rs` | Actual subprocess commands, aliases/positionals, help/CI behavior, Windows CRLF and Unix interactive input, exit codes, spaces in paths, library commands, invalid secret inputs, configuration precedence |
| `library_and_remote.rs` | Atomic snapshots/backups, corrupt-state preservation, concurrent writers, provider URL boundaries, remote node validation, all preset manifests |
| `http.rs` | Loopback-only request retries, attempt bounds, authorization, redirect refusal, malformed and oversized responses |
| `watch.rs` | Real polling process, drift reporting, read-only behavior, interval validation |
| `commands.rs` | Every public command's help/missing arguments, all input/output formats, security/library actions, templates, merge, synchronization |
| `remote_providers.rs` | Complete/truncated GitHub trees, GitLab pagination, branch encoding, URL identity, upstream release states |
| `review_regressions.rs` | Defects reproduced during whole-project review, including failed library commits, read-only preflight, display hierarchy, and Windows casing |
| `native_auth.rs` | Opt-in dummy native-vault store/lookup/update/clear integration |

Numbered-menu unit tests in `src/cli.rs` validate every guided command, all security
actions, and every library action/confirmation.

## Documentation completeness

```powershell
.\tests\docs-reference.ps1 -CheckHelp -CheckExamples
```

This compares the complete command tables against the Rust parser, checks every
command-specific canonical option, all input/output format names and renamed
aliases, validates local links/heading anchors, invokes all twelve help commands,
and executes the getting-started dry-run/scaffold/verify/tree-conversion workflow
in a disposable directory. It does not query public repositories or credentials.

The normal suite never accesses public APIs or real credential vault records.
HTTP tests create bounded loopback servers, explicitly bypass proxies, and use
dummy tokens. CLI tests set an isolated `PTU_DATA_DIR`. Watch tests own and stop
their child processes even when an assertion fails.

## Additional release validation

The default suite validates preset manifests without installing npm dependencies.
Additional checks are available explicitly:

```powershell
cargo test --locked --test native_auth -- --ignored
.\tests\live-commands.ps1
.\tests\template-builds.ps1
```

The vault test creates/removes one unique dummy record. Live checks access public
repositories with `--anonymous` and can fail because of network/provider quotas.
Template checks install dependencies into disposable projects under `target/`,
use a local npm cache, and never deploy. These checks were run during Windows QA;
see the recorded results rather than treating opt-in tests as unexecuted.

Set `PTU_TEST_BINARY` to the absolute path of an extracted executable to rerun
subprocess tests against a packaged artifact:

```powershell
$env:PTU_TEST_BINARY = (Resolve-Path .\dist\ptu-3.0.0-windows-x86_64\ptu.exe).Path
cargo test --locked --test cli --test commands --test watch
cargo test --locked --test native_auth -- --ignored
Remove-Item Env:\PTU_TEST_BINARY
```

After packaging on Windows, the complete artifact check also validates checksums,
required files, Markdown links, and runtime independence:

```powershell
.\tests\package-check.ps1 -IncludeNativeAuth
```

Native vault integration, macOS signing/notarization, packaged runtime dependencies,
cross-architecture builds, and real Termux execution require their matching
environment and are not established by passing Windows tests. The legacy
PowerShell tests remain untouched and are not counted as Rust test results.

Record observed results in `docs/VALIDATION.md`; do not turn intended support
or unexecuted CI into a claim of tested compatibility.
