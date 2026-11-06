# Command reference

Examples use PowerShell from the repository root. In Command Prompt, replace
`.\tree.bat` with `tree.bat`. Paths resolve relative to the caller's directory.
Quote paths and values containing spaces.

## Common behavior

Run `tree.bat` without arguments for the menu. Incomplete command input may
open an interactive flow. Use `--ci` to require noninteractive execution;
it can appear anywhere. `TREE_CI=1`, `true`, or `yes` also enables CI mode.

Named options take separate values: `--format dash`, not `--format=dash`.
Switches such as `--sync` take no value. Unknown options, duplicate options,
and supplying the same value by both position and name are errors.
Prefer named options for automation. PowerShell-style aliases such as
`-StructureFile`, `-MaxDepth`, and `-OutputFile` are accepted where applicable.

Input formats: `dash`, `tab`, `space`, `treesym`, `json`, `yaml`.
Omitting an input format attempts detection; ambiguous files require an explicit
format. Space indentation uses `--space-unit N` (default two).
See [structure formats](FORMATS.md).

Most commands use exit 0 for success, 1 for a negative result, and 2 for invalid
input or execution failure. Command-specific results are described below.
Read `$LASTEXITCODE` immediately after a command in PowerShell.

The `bin/*.bat` wrappers share the public parser; the wrappers for `gittree`
and `library` are `git_tree.bat` and `store.bat`. Backend PowerShell
parameters are internal interfaces and differ from some public options.

## Import

```powershell
.\tree.bat import --ci --structure ".\layout.yaml" --format yaml --output ".\layout.txt" --output-format importable
```

Required: `--structure`, `--output`.
Options: `--format`, `--space-unit`,
`--output-format importable|md|txt|summary` (default `importable`).
Summary prints to the console, but the public parser still requires an output
path. The output parent must exist. Import converts a description; it does not
create the described project.

Positional order: `structure format output output-format`.

## Export

```powershell
.\tree.bat export --ci --root "C:\Projects\app" --format json --output ".\layout.json" --max-depth 0 --show-mode all
```

Required: `--root`, `--format`, `--output`.
Formats: `importable|md|txt|json|yaml`.
`--output-format` aliases `--format`; supply only one.
Options: `--max-depth N`, `--show-mode all|folders|files`,
`--exclude "name,relative/path"`, `--ignore-file PATH`.

Explicit depth/show mode override configuration, then defaults of five and
`all`. Zero depth is unlimited. Files-only mode traverses directories;
JSON/YAML retain required directory ancestors. An incomplete scan fails rather
than producing a successful partial export.

Positional order: `root format output max-depth show-mode exclude ignore-file`.

## Scaffold

```powershell
.\tree.bat scaffold --ci --structure ".\layout.txt" --format dash --target "C:\Projects" --project demo --dry-run
.\tree.bat scaffold --ci --template react-vite --target "C:\Projects" --project web-app
```

Required: `--target`, `--project`, and exactly one of `--structure` or
`--template`. Presets: `react-vite`, `hono-worker`, `monorepo-pnpm`.
Options: `--format`, `--space-unit`,
`--overwrite skip|overwrite|ask` (default `skip`), `--dry-run`.
CI rejects `ask`.

The project name must be one safe Windows directory component. The destination
is `target/project`. Preflight validates the plan before execution; implicit
parent directories are created as needed. Dry-run writes nothing.
Successful execution writes the reserved `_creation_log.txt`.
Runtime failures can leave completed entries behind and report partial counts;
scaffold does not roll back the whole project.

Generated React/Hono projects require Node.js 22.12+. From the generated folder,
run `npm install`, `npm run typecheck`, and `npm run build`.
Hono's build uses `wrangler deploy --dry-run`; the separate deploy script
deploys. For the workspace preset, install pnpm, run `pnpm install`, and
add projects under `apps/` and `packages/`.

Positional file-mode order: `structure format target project`.

## Verify and synchronize

```powershell
.\tree.bat verify --ci --live "C:\Projects\demo" --structure ".\layout.txt" --format dash
.\tree.bat verify --ci --live "C:\Projects\demo" --structure ".\layout.txt" --format dash --sync
```

Required: `--live`, `--structure`.
Options: `--format`, `--space-unit`, `--ignore-file`, `--sync`,
`--delete-extras`. Delete-extras requires sync and removes eligible extra
files and empty directories. Read [synchronization behavior](OPERATIONS.md#synchronization)
before using it.

Verify has no public max-depth option; use the live directory's configuration.
It compares paths and types, not contents.
Exit 0: no remaining in-scope drift; 1: drift remains; 2: invalid input,
incomplete scan, or execution failure. Sync rescans before deciding the result.

Positional order: **`live structure format`**.

## Merge

```powershell
.\tree.bat merge --ci --file-a ".\base.txt" --format-a dash --file-b ".\extra.yaml" --format-b yaml --strategy union --output ".\merged.txt"
```

Required: `--file-a`, `--file-b`, `--output`.
Options: `--format-a`, `--format-b`, `--space-unit-a`,
`--space-unit-b`, `--strategy union|a_over_b|b_over_a` (default union).
Output is importable dash with content/template directives.
Union rejects conflicting types or explicit metadata. Preference strategies
keep the winning type/subtree and preferred metadata, filling missing metadata
from the other input. Backend merge failures return 1; public argument errors
return 2. See [round-trip behavior](FORMATS.md#merge-and-round-trips).

Positional order: `file-a format-a file-b format-b strategy output`.

## Watch

```powershell
.\tree.bat watch --ci --path "C:\Projects\demo" --structure ".\layout.txt" --format dash --max-depth 0
```

Required: `--path`. Options: `--structure`, `--format`, `--max-depth`,
`--ignore-file`. Without a structure, reports layout changes; with one,
reports structural drift. Depth uses configuration, then five; zero is unlimited.
Press Ctrl+C to stop. CI suppresses prompts but watch continues running.
Watch does not synchronize.

Positional order: `path structure ignore-file max-depth`. Supply format by name.

## Remote repository layout

```powershell
.\tree.bat gittree --ci --provider github --repo "https://github.com/tanvirfoysal99/project-tree-utility" --branch develop --format importable --output ".\remote-layout.txt"
```

Required: `--provider github|gitlab`, `--repo`, `--branch`, `--output`,
`--format importable|md|txt|json|yaml`.
Options: `--subfolder`, `--max-depth` (default zero, unlimited),
`--exclude` (comma-separated), `--gitlab-base` (default https://gitlab.com).
Default remote exclusions: `node_modules,.git,dist,build,.next,.wrangler`.
Use HTTPS repository URLs. A self-hosted GitLab base must have the same authority
as the repository URL.

This retrieves tree metadata, not source bytes or history. Public repositories
can be accessed anonymously in CI. Private repositories need a usable credential.
HTTP requests have bounded retries/timeouts. Truncated GitHub trees and invalid
GitLab pagination fail rather than producing a successful partial layout.
No entries can produce exit 1; request/validation failures produce exit 2.

Positional order:
`provider repo branch output format subfolder max-depth exclude gitlab-base`.

## Credentials

Interactive storage uses a masked prompt:

```powershell
.\tree.bat auth --action store --target "https://github.com"
```

For automation, provision a process environment variable through your secret
manager, then name it:

```powershell
.\tree.bat auth --ci --action store --target "https://github.com" --secret-env GITHUB_TOKEN
.\tree.bat auth --ci --action clear --target "https://github.com"
```

Required: `--action store|clear`, `--target`.
Options: `--username` (default oauth2), `--secret-env NAME`,
`--secret-stdin` (reads one token line from piped stdin).
Store accepts one secret channel; CI requires one. Literal token arguments
are unsupported. Targets are HTTPS host/repository URLs without embedded user
information, query, or fragment.
See [credential storage and lookup](OPERATIONS.md#credentials).

Positional order: `action target username`.

## Saved structure library

```powershell
.\tree.bat library --ci --action save --file ".\layout.txt" --format dash --name starter --source manual
.\tree.bat library --ci --action list
.\tree.bat library --ci --action open --name starter
.\tree.bat library --ci --action rename --name starter --new-name starter-v2
.\tree.bat library --ci --action delete --name starter-v2
```

Save copies the input into the library. Format can be detected; source defaults
to manual. Duplicate names receive suffixes. Open prints the saved file path,
rather than launching an application. List prints a table. Missing entries
return 1.

Purge the managed library only by explicitly running
`.\tree.bat library --ci --action purge --yes`.
Purge requires yes and uses the library transaction helpers.

Positional forms: `list`, `save file format source name`, `open name`,
`rename name new-name`, `delete name`, `purge --yes`.

## Security validation

```powershell
.\tree.bat security --ci --action VALIDATE_ALL --file ".\layout.txt" --format dash --base "C:\Projects\demo"
.\tree.bat security --ci --action VALIDATE_PATH --candidate "C:\Projects\demo\src" --base "C:\Projects\demo"
```

VALIDATE_FILE, VALIDATE_NAMES, and VALIDATE_ALL take `--file` and optional
`--format`; all parse and validate schema and names.
VALIDATE_ALL also requires `--base` and checks destinations.
VALIDATE_PATH requires `--candidate` and `--base`.
A rejected containment check returns 1; malformed input can return 2.

Positional forms: `ACTION file format base`, or
`VALIDATE_PATH candidate base`.

## Detection compatibility adapter

```powershell
.\tree.bat detection --ci ANALYSE ".\layout.txt" dash
.\tree.bat detection --ci BUILD_TREE ".\a.txt" dash ".\b.txt" dash union ".\merged.txt"
```

These forms are positional-only. Import and merge are the usual public conversion
and merge commands.

## Version

```powershell
.\tree.bat version --ci
.\tree.bat version --ci --check
```

Without check, CI displays the version only; interactive use offers an update
prompt. `--check-update` aliases check. Exit 0: display completed, no tags, or
no newer tag; 1: newer tag found; 2: check failed.
The current backend checks the legacy GitLab project
`tanvirfoysaltoshin/project-tree-utility`, not this GitHub repository.
