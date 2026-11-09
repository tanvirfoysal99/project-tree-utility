# Changelog

## 3.0.0 — Rust edition

Replaced the brief CLI notes with a complete reference for all 12 commands,
every accepted canonical option, values/defaults, input/output formats, all
actions, positional forms, aliases, environment variables, exit codes, and
troubleshooting. Added first-run and developer/API guides, a tested example
workflow, and source-to-documentation coverage/link checks.

Added tree-symbol export/conversion with `--format treesym` and
`--output-format treesym`, including nested continuation connectors, reusable
metadata, and files-only ancestor context. Export help and the guided menu now
advertise tree-symbol output.

Interactive Windows console input now removes CRLF line endings before parsing;
commands such as `--help` no longer retain an invisible carriage return.

Pre-release command review additionally corrected format detection inside content
directives, display hierarchy and Markdown fencing, read-only overwrite preflight,
in-memory library rollback after failed commits, Windows move protection casing,
literal arguments after `--`, validation before library/network side effects,
security menu inputs, case-insensitive auth actions, and repository URL suffixes.
Version checks handle an unpublished upstream release as an informational result.
Public repository exports can explicitly bypass credential lookup with `--anonymous`.
Portable packages include the referenced source/test/installation documentation.
Library names now use consistent Unicode case matching during save, lookup,
rename, and snapshot validation.

Initial standalone Rust implementation, isolated from the legacy toolkit.

- Native `ptu` CLI with legacy command names, aliases, positional forms, and CI mode.
- Strict reusable JSON/YAML/dash formats, text indentation formats, content
  directives, deterministic normalization, and conflict-aware merge.
- Complete directory scans, shared scope configuration, scaffold preflight,
  opt-in synchronization, conservative deletion, and polling-based monitoring.
- Embedded React/Vite, Hono Worker, and pnpm workspace presets.
- Independent atomic saved-layout library with locking and previous snapshots.
- Native Windows/macOS vault integration and Git credential-helper integration
  for Linux/Termux; bounded HTTPS GitHub/GitLab metadata retrieval.
- Separate documentation, regression tests, installation/packaging scripts,
  and a standalone CI template.

Behavioral differences are listed in [Migration](docs/MIGRATION.md).
Platform validation status is recorded in [Validation](docs/VALIDATION.md).
