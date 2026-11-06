# Changelog

All notable changes to Project Tree Utility will be documented here.

Format: `## [version] - YYYY-MM-DD`
Change types: `Added`, `Changed`, `Fixed`, `Removed`, `Security`

Versioned entries describe historical releases. For the current command contract,
see [the command reference](docs/CLI.md).

---

## [Unreleased]

### Fixed

- Resolved committed merge conflicts in command backends, wrappers, and documentation.
- Corrected library paths to resolve under `data/store_trees`, normalized legacy
  index paths, and rejected invalid indexes and paths outside the library.
- Rejected reparse points in write destinations and existing ancestors, and
  validated scaffold project names in file and template modes.
- Replaced recursive sync directory deletion with empty-directory deletion so
  excluded, hidden, depth-limited, and newly created children are preserved.
- Corrected verification metadata formatting that prevented sync with matched files.
- Moved interpolated Batch command bodies and generated VBScript/PowerShell
  engines into permanent parameterized scripts and fixed stale exit-code checks.
- Added scaffold preflight checks, implicit parent creation, terminating error
  handling, accurate counters, and partial-failure reporting.
- Preserved template directory indicators and empty directories when parsing nodes.
- Made importable dash exports root-relative and removed presentation headers.
- Aligned YAML sequence parsing and writing, preserved quoted and multiline scalar
  content, and rejected unsupported syntax and duplicate properties explicitly.
- Preserved indentation during format detection, inspected multiple lines, and
  reported ambiguous flat tab/space layouts instead of guessing.
- Enforced complete hierarchy and node validation, including depth transitions,
  file parents, duplicate normalized paths, and invalid Windows path components.
- Unified CLI parsing for all Batch entry points, accepted CI flags in any
  position, kept all arguments, and made missing CI inputs fail without prompts.
- Corrected verify argument order and preserved backend exit statuses through
  routing, including version update/error results and library operation failures.
- Unified export, verify, and watch scanning with hidden-entry support, explicit
  scan errors, identical expected/actual scope, and refusal to sync incomplete scans.
- Kept move heuristics separate from authoritative differences, preserved possible
  move sources, and rescanned after synchronization for accurate reports/status.
- Added serialized library transactions, atomic index replacement with backups,
  file-operation rollback, and journal recovery after process interruption.
- Preserved merge content/templates and resolved type conflicts explicitly; added
  lossless Base64 content directives for dash format.
- Unified credential vault storage/read/delete, allowed anonymous CI repository
  requests, and replaced literal secret arguments with environment/stdin input.
- Extended command exception boundaries to argument-file loading and remote
  output, with contextual errors and partial-sync operation counts.
- Applied explicit/config/default option precedence and consistent export show
  modes, including nested files and unlimited depth zero.
- Added bounded HTTP timeouts/retries, encoded branch values, validated API
  responses/pagination, and refused truncated remote output.
- Reworked watch lifecycle with startup-safe subscriptions, debounce, scoped event
  filtering, overflow/error recovery, periodic rescans, and guaranteed cleanup.
- Removed remaining wrapper argument temp files, corrected PowerShell 5.1 colors,
  wired library verification preload, and completed runnable template dependencies.

### Added

- Windows PowerShell 5.1 regression suites covering path safety/library/sync,
  scaffolding/formats, structure validation/CLI, scans/merge/transactions/credentials,
  and runtime/export/HTTP/watch behavior.
- An aggregate regression runner, GitHub/GitLab Windows CI, and optional
  disposable React/Vite and Hono template build checks.
- Dedicated command, format, operations/recovery, and test coverage guides.

### Changed

- Replaced issue-number test filenames with descriptive coverage-based names.
- Made GitHub CI use the shared test runner and fail when no suites are found.
- Rewrote current documentation against the implemented CLI, corrected repository
  links, and documented the two-branch develop/master workflow.
- Documented the version checker's remaining legacy GitLab target explicitly.

## [2.2.0] - 2026-07-11

### Added

- **`.treeignore` support** — drop a `.treeignore` file in any directory to
  configure excludes, max depth, and show mode for export and watch without
  interactive prompts. Supports `exclude:`, `maxdepth:`, `showmode:`, and
  `template:` directives.

- **Watch mode** (`bin/watch.bat` + `src/watch.ps1`) — monitors a directory
  with `FileSystemWatcher` and reports structural drift in real time. Optionally
  compares against a structure file on every change event.

- **Template presets** — scaffold a project from a built-in template without
  needing a structure file. Available templates: `react-vite`, `hono-worker`,
  `monorepo-pnpm`. Accessible via `--template <name>` flag or the interactive
  picker inside `scaffold.bat`.

- **Inline content directives** — structure file entries can carry `@content:`
  (literal string) or `@template:` (named preset) directives to seed file
  content at scaffold time.

- **JSON structure file format** — import, export, scaffold, verify, and merge
  using `.json` tree files. Supports `children`, `entries`, `type`, `template`,
  and `contentDirective` properties.

- **YAML structure file format** — same as JSON but in YAML. Includes a
  hand-rolled parser that handles nested blocks, lists, and scalar values.

- **`--sync` flag in verify** — after detecting drift, automatically creates
  missing folders and files on disk to reconcile the live directory with the
  structure file. Optionally deletes extras with `--delete-extras`.

- **JSON and YAML export formats** — `export.bat` and `git_tree.bat` now
  offer JSON and YAML as output format options alongside Markdown, plain text,
  and importable dash layout.

- **Credential Manager (`bin/auth.bat` + `src/auth.ps1`)** — stores and clears
  PATs and tokens in the Windows credential vault using Git Credential Manager
  or `cmdkey.exe` as fallback. Secrets are never written to disk.

- **`--ci` non-interactive mode** — all subcommands now accept a `--ci` flag
  and respect the `TREE_CI` environment variable. In CI mode all interactive
  prompts are skipped, `pause` calls are suppressed, and arguments are
  positional.

- **File metadata in verify report** — matched files now show file size and
  last-modified timestamp. A summary line at the bottom of the metadata section
  shows total matched count, total size, and the most recently modified file.

- **Color output** — ANSI color applied consistently across `verify.ps1`,
  `watch.ps1`, and `scaffold_validate.ps1` via a shared `Write-Color` helper
  in `_shared.ps1`. Green = OK, Red = error/missing, Yellow = warn/extra,
  Cyan = sync actions, Gray = headers and neutral info.

- **`version` subcommand** (`bin/version.bat` + `src/version.ps1`) — displays
  the current version and optionally checks the GitLab releases API for a newer
  tag. Supports `--check` and `--ci`.

- **`export.ps1` refactor** — export logic moved from a VBScript-generated
  temp file into a proper standalone `src/export.ps1` with a clean parameter
  interface, making it directly callable from CI pipelines.

- **`Get-LimitedItems` moved to `_shared.ps1`** — previously only available
  inside `verify.ps1`; now shared so `watch.ps1` can use it without a
  duplicate definition.

### Fixed

- `verify.ps1` was not passing `$IgnoreFile` to `Get-ExcludeList`, so
  `.treeignore` exclusions were silently ignored during verify runs.

- `watch.ps1` crashed when a structure file was provided because
  `Get-LimitedItems` was undefined in its scope.

- `scaffold.bat` had no interactive template discovery — users had to already
  know the template name to use `--template`. The Step 0 picker now shows
  available templates before asking for a file path.

### Security

- All structure file entries are validated for path traversal, dangerous names,
  and format consistency before any disk write — unchanged from v2.1.x.
- Credential handling keeps tokens out of project files; persistent credentials
  are managed by Windows Credential Manager.
