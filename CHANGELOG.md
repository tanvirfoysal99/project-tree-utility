# Changelog

All notable changes to Project Tree Utility will be documented here.

Format: `## [version] - YYYY-MM-DD`
Change types: `Added`, `Changed`, `Fixed`, `Removed`, `Security`

---

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
  tag. Supports `--check`, `--ci`, and an optional `-Token` parameter for
  private instances.

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
- PAT handling in `git_tree.ps1` and `auth.ps1` uses `SecureString` and is
  never persisted to disk.
