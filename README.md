# Project Tree Utility

A zero-dependency project structure toolkit for Windows — built entirely with
Batch and PowerShell. No Node.js, no Python, no Git installation required.
Works on any Windows 10/11 machine out of the box.

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

### merge
Combines two structure files into one using a tree-aware merge algorithm.

```bat
tree.bat merge
```

Merge strategies:
- `union` — keep all unique entries from both files
- `a_over_b` — File A wins on conflicts, B fills gaps
- `b_over_a` — File B wins on conflicts, A fills gaps

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

### watch
Monitors a directory with `FileSystemWatcher` and reports structural
drift in real time. Optionally compares against a structure file on
every change event.

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

Supports GitHub and GitLab (including self-hosted instances). PAT is
collected securely via masked prompt and never written to disk.

### auth
Stores or clears a credential (PAT or token) in the Windows credential
vault using Git Credential Manager or `cmdkey.exe` as fallback. The
secret is never written to disk.

```bat
tree.bat auth store "git:https://gitlab.com" "oauth2"
tree.bat auth clear "git:https://gitlab.com"
```

### library
Saves, lists, opens, renames, and deletes named structure files in a
local library stored under `data/`.

```bat
tree.bat library
```

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
- Arguments are passed positionally
- Exit codes are the only output signal

```bat
set TREE_CI=1
tree.bat export --ci "C:\myproject" importable "output.txt" 5 all
tree.bat verify --ci "C:\myproject" "structure.txt" "dash"
tree.bat version --check --ci
```

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
- PATs and tokens are never written to disk; they go directly to the OS
  credential vault via Git Credential Manager or `cmdkey.exe`
- The `--ci` flag never bypasses security checks — it only suppresses
  interactive prompts

---

## License

**Source-Available / Custom Non-Commercial License**

This project is open for viewing, personal use, educational purposes, and non-commercial development. However, commercial entities, corporations, or individuals seeking to integrate or monetize this software **cannot own, close, or commercially exploit this project** without explicit written permission.

- **Personal & Educational Use:** Free to use, modify, and distribute indefinitely.

- **Commercial / Enterprise Use:** You must request permission and agree to specific terms & conditions before usage.

For full legal terms, please review the `LICENSE` file in this repository.

---

## Author

**Tanvir Foysal Toshin**
tanvirfoysaltoshin@gmail.com
[gitlab.com/tanvirfoysaltoshin/project-tree-utility](https://gitlab.com/tanvirfoysaltoshin/project-tree-utility)
