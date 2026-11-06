# Project Tree Utility

A zero-dependency project structure toolkit for Windows — built entirely with
Batch and PowerShell. No Node.js, no Python, no Git installation required.
Works on any Windows 10/11 machine out of the box.

The utility itself needs no external runtime. Generated React/Vite and Hono
projects require Node.js 22.12+ and their declared npm dependencies; the pnpm
workspace template also requires pnpm. Each template includes a README and build
scripts. Dependency setup follows the [Vite guide](https://vite.dev/guide/) and
[Hono Workers guide](https://hono.dev/docs/getting-started/cloudflare-workers).

**Version:** 2.2.0 · **Platform:** Windows 10/11 · **Requirements:** PowerShell 5.1+

---

## What it does

Project Tree Utility lets you define, visualise, scaffold, verify, and sync
project directory structures using plain text files. It is useful for:

- Bootstrapping new projects from a saved structure template
- Cloning the layout of a GitHub or GitLab repository without cloning the code
- Verifying that a live directory still matches its intended structure
- Merging two project structures into one
- Watching a directory for live structural drift

---

## Project structure

```
project-tree-utility/
├── tree.bat                  ← entry point (run this)
├── bin/                      ← CLI wrappers
│   ├── import.bat
│   ├── export.bat
│   ├── merge.bat
│   ├── scaffold.bat
│   ├── verify.bat
│   ├── watch.bat
│   ├── security.bat
│   ├── git_tree.bat
│   ├── auth.bat
│   ├── store.bat
│   ├── detection.bat
│   └── version.bat
├── src/                      ← PowerShell backend
│   ├── internal/
│   │   └── _shared.ps1       ← shared library (do not run directly)
│   ├── export.ps1
│   ├── import.ps1
│   ├── scaffold.ps1
│   ├── wrapper_actions.ps1
│   ├── detection.ps1
│   ├── verify.ps1
│   ├── watch.ps1
│   ├── merge_tree.ps1
│   ├── scaffold_validate.ps1
│   ├── git_tree.ps1
│   ├── store.ps1
│   ├── auth.ps1
│   └── version.ps1
└── data/
    ├── store_data.json        ← library index (auto-generated)
    └── store_trees/           ← saved structure file copies (auto-generated)
```

---

## Installation

1. Download or clone the repository
2. Place the folder anywhere on your machine
3. Double-click `tree.bat` to open the interactive menu

No installer, no PATH changes, no dependencies.

```bat
git clone https://gitlab.com/tanvirfoysaltoshin/project-tree-utility.git
cd project-tree-utility
tree.bat
```

---

## Quick start

### Interactive menu

Double-click `tree.bat` or run it from a terminal:

```bat
tree.bat
```

You will see a numbered menu. Every feature is reachable from here.

### CLI passthrough

Every subcommand can be called directly without going through the menu:

```bat
tree.bat export
tree.bat scaffold --template react-vite
tree.bat verify --ci "C:\myproject" "structure.txt" "dash"
tree.bat version --check
tree.bat watch "C:\myproject"
```

---

## Subcommands

### import
Reads any supported structure file format and converts it to another format.

Supported input formats: dash layout, tab-indented, tree symbols (`tree /f`
output), fixed-space indent, JSON, YAML.

```bat
tree.bat import
```

### export
Scans a live directory and writes its structure to a file. Respects
`.treeignore` if present in the scanned directory.

```bat
tree.bat export
tree.bat export --ci "C:\myproject" importable "output.txt"
```

Output formats: Markdown, plain text, importable dash layout, JSON, YAML.

Export option precedence is explicit CLI/backend options, then `.treeignore`,
then defaults (depth 5 and all entries). Depth `0` means unlimited. Files-only
mode traverses subdirectories in every format; JSON/YAML retain the directory
ancestors needed to represent nested files and omit unrelated empty folders.

### merge
Combines two structure files into one using a tree-aware merge algorithm.

```bat
tree.bat merge
```

Merge strategies:
- `union` — keep all unique entries from both files
- `a_over_b` — File A wins on conflicts, B fills gaps
- `b_over_a` — File B wins on conflicts, A fills gaps

Merge preserves content and template metadata, including multiline or empty
content. `union` rejects conflicting file/directory types or explicit content
and template values. The other strategies keep the winning type and its subtree;
missing metadata can be filled from the other input. Dash output uses an
`@content64:` UTF-8 Base64 directive when needed to preserve literal content.
This encoding preserves text; it is not encryption.

### scaffold
Creates a real directory tree on disk from a structure file. Supports
dry-run preview, overwrite modes, and built-in template presets.

```bat
tree.bat scaffold
tree.bat scaffold --template react-vite
tree.bat scaffold --template hono-worker
tree.bat scaffold --template monorepo-pnpm
```

Built-in templates:

| Name | Description |
|---|---|
| `react-vite` | React + Vite + TypeScript |
| `hono-worker` | Hono on Cloudflare Workers |
| `monorepo-pnpm` | pnpm monorepo workspace |

### verify
Compares a structure file against a live directory and reports missing
and extra entries, file sizes, and last-modified timestamps.

```bat
tree.bat verify
tree.bat verify --sync        ← create missing entries on disk
tree.bat verify --ci "C:\myproject" "structure.txt" "dash"
```

Export, verify, and watch share a scope based on relative paths, exclusions, and
maximum depth. Hidden entries are included. Expected entries outside that scope
are reported separately rather than called missing. Any enumeration error or
unfollowed reparse point makes the scan incomplete: export and sync fail before
writing instead of reporting a partial scan as successful.

Move matches are suggestions, not confirmed moves. Sync creates all missing
destinations and preserves possible move sources (and their containing folders)
even with `--delete-extras`. It then rescans and reports the final drift; a clean
result returns `0`, remaining differences return `1`, and scan or write failures
return `2`. Excluded or unscanned descendants are never recursively deleted.

### watch
Monitors a directory with `FileSystemWatcher` and reports structural
drift in real time. Optionally compares against a structure file after
batches of relevant changes.

Watch subscribes before its first snapshot, batches relevant events over 250 ms,
ignores excluded/deeper events, and rescans after watcher errors or overflow.
A periodic five-second rescan also reconciles missed events. All subscriptions,
queued events, and watcher resources are cleaned up on exit. Explicit depth `0`
is unlimited. Incomplete snapshots are reported and retried rather than shown
as clean results.

```bat
tree.bat watch
```

### security
Validates a structure file for path traversal attacks, dangerous entry
names, and format consistency before any disk write.

```bat
tree.bat security
```

### gittree
Exports the file/folder tree of any public or private GitHub or GitLab
repository over HTTPS — no Git installation required.

```bat
tree.bat gittree
```

Supports GitHub and GitLab (including self-hosted instances). PATs are read from
the vault or collected via a masked prompt; plaintext secrets are not saved to
project files.

API calls use a 15-second timeout and at most two retries for connection failures,
rate limits, and transient HTTP errors. Retry delays are capped at eight seconds.
Branch values are URL encoded; malformed pages, pagination loops, and truncated
GitHub trees fail explicitly before output is written. This follows the
[GitHub tree API completeness contract](https://docs.github.com/en/rest/git/trees).

### auth
Stores or clears a credential (PAT or token) using the Windows credential vault
API. Remote export reads that same vault and can also read existing Git
Credential Manager credentials. Public repositories support anonymous CI use.
Secrets are not written to project files or passed to helpers as process arguments.

```bat
tree.bat auth store "git:https://gitlab.com" "oauth2"
tree.bat auth clear "git:https://gitlab.com"
```

Interactive storage uses a masked prompt. In CI, supply an environment-variable
name or a single secret line on standard input; literal secret arguments are
rejected:

```bat
tree.bat auth store "git:https://gitlab.com" "oauth2" --ci --secret-env MY_PAT
tree.bat auth store "git:https://gitlab.com" "oauth2" --ci --secret-stdin
```

The second command reads from redirected or piped input. Credential keys preserve
the HTTPS host, port, and optional repository path. Remote lookup checks the
repository key, then the host key. Clearing a key is idempotent.

### library
Saves, lists, opens, renames, and deletes named structure files in a
local library stored under `data/`.

```bat
tree.bat library
```

Library updates are serialized by a file lock. Index writes use atomic replacement
and retain the previous index as `store_data.json.bak`. A transaction journal
allows interrupted file/index changes to be recovered on the next access; failed
commits roll back staged adds, renames, and deletes. Corrupt or ambiguous recovery
state is preserved and reported for repair instead of being reset to an empty
library. Purge uses the same lock and leaves a valid empty index.

### version
Displays the current version and optionally checks GitLab for a newer
release.

```bat
tree.bat version
tree.bat version --check
tree.bat version --check --ci
```

Exit codes: `0` = up to date, `1` = update available, `2` = offline/error.

---

## Structure file formats

The toolkit reads and writes several formats:

### Dash layout (recommended)
```
- src/
-- components/
--- Button.tsx
-- index.ts
- package.json
```
Depth is indicated by the number of leading dashes. Folders should have
a trailing `/`.

Importable exports contain only dash entries relative to the scanned directory;
they omit summary headings and the scanned root itself. Exporting and importing
the file therefore preserves the hierarchy when scaffolding into a new project.

### Tab-indented
```
src/
	components/
		Button.tsx
	index.ts
package.json
```

### Tree symbols (Windows `tree /f` output)
```
├── src/
│   ├── components/
│   │   └── Button.tsx
│   └── index.ts
└── package.json
```

### JSON
```json
{
  "name": "src",
  "type": "directory",
  "children": [
    { "name": "index.ts", "type": "file" }
  ]
}
```

### YAML
```yaml
- name: src
  type: directory
  children:
    - name: index.ts
      type: file
```

The dependency-free YAML reader supports tree mappings and block sequences,
including standalone `-` markers, quoted scalar values, and literal content
blocks (`|`, `|-`, `|+`). Double-quoted values use JSON-compatible escapes.
Literal blocks preserve relative indentation, comments, and blank lines.
Anchors, aliases, tags, folded blocks, nonempty flow collections, duplicate keys,
and unknown tree properties are rejected with an error instead of being ignored.

Directory nodes support `type: directory` (also `dir`, `folder`, or `tree`),
`IsDir: true`, a trailing `/`, or a `children` property, including an empty one.

### Inline content directives
Any dash-layout file can attach content to a file entry:

```
-- src/index.ts @content:export default {}
-- src/worker.ts @template:hono-worker
```

`@content:` writes the literal string as the file's initial content.
`@template:` pulls content from a named built-in template.

---

## .treeignore

Drop a `.treeignore` file in any directory to configure export and watch
behaviour for that directory. It is never required.

```
# Folders to exclude
node_modules
.git
dist
.next

# Options
maxdepth: 4
showmode: all
```

Supported directives: `exclude:`, `maxdepth:`, `showmode:` (`all`,
`folders`, `files`), `template:`.

---

## CI mode

Every subcommand supports a `--ci` flag and a `TREE_CI` environment
variable for non-interactive pipeline use. In CI mode:

- All interactive prompts are skipped
- `pause` calls are suppressed
- Required arguments are checked before running; missing values fail without prompting
- Named options are recommended; documented positional forms remain supported
- Exit codes are preserved through every wrapper (diagnostic output may also be printed)

```bat
set TREE_CI=1
tree.bat export --ci "C:\myproject" importable "output.txt" 5 all
tree.bat verify --ci "C:\myproject" "structure.txt" "dash"
tree.bat version --check --ci
```

`--ci` may appear before the subcommand or anywhere after it. `TREE_CI=1`,
`true`, or `yes` enables the same mode. Direct `bin/*.bat` calls use the same
parser. Relative CLI paths resolve against the caller's working directory.
Use named options to avoid confusing a format with an ignore-file path:

```bat
tree.bat --ci verify --live "C:\myproject" --structure "structure.txt" --format dash
tree.bat import --ci --structure "structure.txt" --format dash --output "converted.txt"
tree.bat export --ci --root "C:\myproject" --format json --output "tree.json"
tree.bat scaffold --ci --template react-vite --target "C:\projects" --project my-app
tree.bat merge --ci --file-a a.txt --format-a dash --file-b b.txt --format-b dash --output merged.txt
tree.bat security --ci VALIDATE_ALL structure.txt dash "C:\myproject"
tree.bat library --ci save structure.txt dash manual "My tree"
tree.bat library --ci rename "My tree" "New name"
tree.bat library --ci delete "New name"
tree.bat library --ci purge --yes
tree.bat watch --ci --path "C:\myproject" --structure structure.txt --format dash
```

The verify positional contract is **live directory, structure file, optional
format**. Export retains **root, output format, output file, optional depth,
show mode, excludes, ignore file**. Remote export retains all nine positional
arguments: **provider, repository URL, branch, output file, output format,
subfolder, depth, excludes, GitLab base URL**. The router does not truncate them.

General exit codes are `0` for success, `1` for drift, a rejected operation,
or a missing library entry, and `2` for invalid input or execution/setup errors.
Version uses `1` for an available update and `2` for a failed update check.
Watch runs until stopped and never prompts in CI. CI scaffolding rejects
`--overwrite ask`; destructive library purge requires `--yes`.

Structure validation checks every meaningful line or node. Skipped depth levels,
file parents, conflicting or duplicate paths (case insensitive), malformed node
properties, and invalid Windows path components are rejected before use. Flat
tab/space layouts without indentation are ambiguous; specify `--format` for them.
Filename checks apply to each path component, including device names, alternate
data streams, and trailing dots/spaces. Names such as `file..txt` remain valid.

---

## Development

### Requirements

- Windows 10 or 11
- PowerShell 5.1 (built into Windows — no install needed)
- No other dependencies

### Repository layout for contributors

All PowerShell logic lives in `src/`. The `.bat` files in `bin/` are
thin wrappers that handle argument parsing, CI mode detection, and
handoff to the PS1 backend. Business logic belongs in PS1, not in BAT.

Scaffolding runs in `src/scaffold.ps1`; conversion runs in `src/import.ps1`.
Menu operations use fixed actions in `src/wrapper_actions.ps1`, receiving input
as environment values rather than interpolating it into script source. Scaffold
validates its plan before writing, creates implicit parent directories, and
returns a failure with successful-operation counts if a write fails. It does
not roll back files already created before a runtime failure.

Batch wrappers do not generate temporary scripts or argument files. PowerShell
5.1 console colors use `Write-Host` so redirected output stays plain text.
The regression runner is `tests/run-regressions.ps1`; GitHub Actions runs it on
Windows and separately builds the generated templates. The GitLab job requires
a Windows shell runner with the `windows` tag. Optional local template build
checks are in `tests/template-builds.ps1`; they download npm dependencies into
temporary projects and use a Wrangler dry run without deploying anything.

The shared library `src/internal/_shared.ps1` is dot-sourced by every
PS1 script. If you add a utility function that more than one script
needs, add it there. Functions include:

- `Read-StructureFile` — parses any supported format into a flat entry list
- `Get-StructureFormat` — auto-detects format from file content
- `Get-ExcludeList` — resolves excludes from `.treeignore` + extra args
- `Get-TreeConfig` — reads `.treeignore` directives
- `Get-LimitedItems` — depth-limited recursive directory scan
- `Test-SafePath` — path traversal guard
- `Test-DangerousName` — entry name safety check
- `Get-FileStub` — generates boilerplate file content by extension
- `Get-StructureEntryContent` — resolves `@content:` and `@template:` directives
- `Write-Color` — ANSI color output for console messages
- `Format-FileSize` — human-readable file size formatting

### Adding a new subcommand

1. Create `src/yourcommand.ps1` with a `param()` block. Include `-Ci [switch]`
2. Create `bin/yourcommand.bat` following the pattern of any existing `.bat`:
   detect `--ci` / `TREE_CI`, skip `pause` in CI mode, pass `%*` through
3. Add the subcommand to `tree.bat`:
   - Passthrough line in the CLI dispatch block
   - Missing-file check
   - Menu entry with a number
   - Handler in the menu choice block

### Adding a new template preset

In `src/internal/_shared.ps1`, find the `Get-TemplatePreset` function and
add a new entry following the existing pattern. Each entry is a list of
objects with `Path`, `IsDir`, and optionally `Content` properties.

Then register the name in `bin/scaffold.bat`'s Step 0 template picker menu.

### Adding a new structure file format

In `src/internal/_shared.ps1`:

1. Add a detection branch in `Get-StructureFormat`
2. Add a parser branch in `Read-StructureFile`
3. Add a validator branch in `Confirm-StructureFormat`

---

## Security model

- Structure files are validated before any disk write (format, name safety,
  path traversal)
- All write paths are checked against the allowed base with `Test-SafePath`
- PATs and tokens go directly to protected OS credential storage; plaintext
  secrets are not written to project files or sent as command-line arguments
- The `--ci` flag never bypasses security checks — it only suppresses
  interactive prompts

---

## License

**Source-Available / Custom Non-Commercial License**

This project is open for viewing, personal use, educational purposes, and non-commercial development. However, commercial entities, corporations, or individuals seeking to integrate or monetize this software **cannot own, close, or commercially exploit this project** without explicit written permission.

- **Personal & Educational Use:** Free to use, modify, and distribute indefinitely.

- **Commercial / Enterprise Use:** You must request permission and agree to specific terms & conditions before usage.

For full legal terms, please review the `LICENSE` file in this repository.

**For commercial licensing or corporate use inquiries, please contact me at tanvirfoysaltoshin@gmail.com.**

---

## Author

**Tanvir Foysal Toshin**

tanvirfoysaltoshin@gmail.com

[gitlab.com/tanvirfoysaltoshin/project-tree-utility](https://gitlab.com/tanvirfoysaltoshin/project-tree-utility)
