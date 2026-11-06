# Project Tree Utility

A Windows toolkit for describing, exporting, scaffolding, merging, verifying, and
watching project directory structures through an interactive menu or command line.

**Version:** 2.2.0. **Platform:** Windows 10/11 with Windows PowerShell 5.1.
The utility requires no package installation. Generated application templates
require Node.js 22.12+; the workspace preset also requires pnpm.

## Installation

Download and extract the complete repository from
[GitHub](https://github.com/tanvirfoysal99/project-tree-utility), then run
`tree.bat`. Alternatively, with Git installed:

```powershell
git clone https://github.com/tanvirfoysal99/project-tree-utility.git
Set-Location project-tree-utility
.\tree.bat
```

Keep `tree.bat`, `bin`, and `src` together. No installer or PATH change is
needed. Double-clicking `tree.bat` opens the interactive menu.

## Quick start

Run these examples in PowerShell from the utility folder, substituting your paths.
Quote values containing spaces.

Export a reusable layout:

```powershell
.\tree.bat export --ci --root "C:\Projects\app" --format importable --output ".\structure.txt" --max-depth 0
```

Preview creation, then scaffold a project:

```powershell
.\tree.bat scaffold --ci --structure ".\structure.txt" --format dash --target "C:\Projects" --project demo --dry-run
.\tree.bat scaffold --ci --structure ".\structure.txt" --format dash --target "C:\Projects" --project demo
```

Compare the new project with its intended layout:

```powershell
.\tree.bat verify --ci --live "C:\Projects\demo" --structure ".\structure.txt" --format dash
```

Verify defaults to five levels unless configured otherwise. For unlimited depth,
put `maxdepth: 0` in the live directory's `.treeignore`.

Exports contain names and types, not existing file bytes. Scaffold creates stubs
unless the structure supplies content or template directives.

## Commands

| Command | Purpose |
| --- | --- |
| `import` | Validate and convert a structure into reusable dash or display text |
| `export` | Export a local directory layout |
| `scaffold` | Create a project from a structure or preset |
| `verify` | Compare a directory with a structure; optionally synchronize |
| `merge` | Combine structures with a conflict strategy |
| `watch` | Monitor layout changes and optional structural drift |
| `gittree` | Export GitHub/GitLab repository layout through its API |
| `auth` | Store/clear a remote credential in Windows Credential Manager |
| `library` | Save, list, locate, rename, delete, or purge saved structures |
| `security` | Validate structure files, names, and path containment |
| `detection` | Compatibility analysis/merge adapter |
| `version` | Display the version or check the configured upstream |

Use `--ci` for noninteractive execution. Missing required inputs then fail
instead of opening menus or prompts.

Built-in presets: `react-vite`, `hono-worker`, `monorepo-pnpm`. Scaffold
does not install packages or deploy applications.

## Documentation

- [Commands, options, examples, and exit codes](docs/CLI.md)
- [Structure formats and content directives](docs/FORMATS.md)
- [Configuration, synchronization, credentials, and recovery](docs/OPERATIONS.md)
- [Test suite coverage and execution](tests/README.md)
- [Development and the develop/master workflow](CONTRIBUTING.md)
- [Change history](CHANGELOG.md)

## Limitations

The tool compares directory structure, not file contents. Layout exports do not
preserve bytes, timestamps, permissions, or Git history. Local scans include hidden
items and refuse incomplete results for export/sync. Junctions and other reparse
points are not traversed.

The current version checker queries the legacy GitLab project
`tanvirfoysaltoshin/project-tree-utility`, rather than this GitHub repository.
Its result is not authoritative for GitHub updates.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE.md). Read the license for permitted
uses and distribution conditions.
