# Contributing

Work from this directory. Keep changes independent of the legacy project. Use
stable Rust and the committed lockfile. Do not commit `target/`, `dist/`, local
toolchains, tokens, or private structure fixtures.

## Required checks

```sh
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
cargo build --release --locked
git diff --check
```

Update command/format docs when behavior changes. Add regression tests for real
failure modes, especially parsing ambiguity, path containment, incomplete scans,
destructive sync, and interrupted storage. Prefer temporary fixture trees and
loopback HTTP servers over live services. Real vault tests and generated-app
dependency installs must be explicitly opted into.

## Design rules

- Keep the normalized entry model separate from presentation and mutation.
- Validate imported and remote paths with the same portable naming rules.
- Never turn incomplete scans or failed requests into successful empty results.
- Validate an entire mutation plan before writing. Revalidate destinations at use.
- Do not invoke shells to interpret user-provided command text or file content.
- Keep secret arguments out of process command lines, logs, and diagnostics.
- Preserve the independent Rust data namespace and document migrations explicitly.
- Test native platform behavior before declaring a platform release supported.

Use `docs/RELEASING.md` when preparing artifacts. The nested CI workflow is a
standalone-project template; it is not automatically active in the parent repo.

The [developer guide](docs/DEVELOPER_GUIDE.md) documents module/API contracts and
the required command-change workflow. The [complete CLI reference](docs/CLI.md)
must describe every canonical option, value/default, positional form, and action.
Check documentation against the parser and real help before packaging:

```powershell
.\tests\docs-reference.ps1 -CheckHelp -CheckExamples
```
