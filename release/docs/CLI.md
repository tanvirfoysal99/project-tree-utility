# Complete command and option reference

**Project Tree Utility, Rust edition 3.0.0. There are 12 public commands.**

This is the complete user-facing CLI reference. Each command below lists every
canonical option accepted by the current parser, its purpose, required inputs,
allowed values, defaults, examples, positional syntax, and exit behavior.
For a first run, use [Getting started](GETTING_STARTED.md). For source development,
see [Developer guide](DEVELOPER_GUIDE.md). Structure-file syntax is specified in
[Formats](FORMATS.md).

## Contents

- [Where to type commands](#where-to-type-commands)
- [All 12 commands](#all-12-commands)
- [How command syntax works](#how-command-syntax-works)
- [Global help, version, and CI options](#global-help-version-and-ci-options)
- [Formats: all input and output types](#formats-all-input-and-output-types)
- [Depth, filtering, and configuration](#depth-filtering-and-configuration)
- [1. import](#1-import)
- [2. export](#2-export)
- [3. scaffold](#3-scaffold)
- [4. verify](#4-verify)
- [5. merge](#5-merge)
- [6. watch](#6-watch)
- [7. gittree](#7-gittree)
- [8. auth](#8-auth)
- [9. library](#9-library)
- [10. security](#10-security)
- [11. detection](#11-detection)
- [12. version](#12-version)
- [Option lookup by purpose](#option-lookup-by-purpose)
- [Compatibility aliases](#compatibility-aliases)
- [Environment variables](#environment-variables)
- [Exit codes and automation](#exit-codes-and-automation)
- [Errors and corrections](#errors-and-corrections)

## Where to type commands

There are two different places to enter commands. The executable name belongs
in your operating-system terminal command, but not inside the app's own prompt.

| Where you are | Example to type |
| --- | --- |
| Inside the app, after `ptu>` | `export --root "E:/Projects/app" --format treesym --output "E:/Projects/tree.txt"` |
| PowerShell, in the folder containing the portable executable | `.\ptu.exe export --root "E:/Projects/app" --format treesym --output "E:/Projects/tree.txt"` |
| CMD, in that executable folder | `ptu.exe export --root "E:/Projects/app" --format treesym --output "E:/Projects/tree.txt"` |
| Linux/macOS/Termux shell, with a compatible executable in the current directory | `./ptu export --root ./app --format treesym --output ./tree.txt` |
| Any supported shell after installation on `PATH` | `ptu export --root ./app --format treesym --output ./tree.txt` |

**The examples in the rest of this reference use `ptu` as the executable name.**
If you are inside `ptu>`, remove that leading `ptu`. If it is not on `PATH`,
replace it with `.\ptu.exe`, `./ptu`, or its full path as appropriate.

Do not type the displayed prompt text (`ptu>`, `PS>`, or `$`). Press Enter after
the command. Use forward slashes in paths inside `ptu>`; quote paths with spaces.
Relative paths resolve from the process's working directory, not automatically
from the executable, layout file, or output file directory. Absolute paths avoid
ambiguity when starting the portable executable by double-clicking it.

The interactive prompt executes PTU commands. Shell assignments, `cd`, pipes,
and redirection belong in CMD/PowerShell/Bash outside that prompt.

### Interactive menu

Run the executable with no arguments on a terminal to open the menu. Enter a
number for a guided operation or type a full PTU command without the executable.

| Menu number | Operation | What it asks for |
| --- | --- | --- |
| `1` | Import | Structure, input format, output path, output format |
| `2` | Export | Root, output format, output path, maximum depth |
| `3` | Scaffold a structure file | Structure, format, target, project name, overwrite policy |
| `4` | Verify | Live root, structure, format |
| `5` | Merge | Both files and formats, strategy, output |
| `6` | Watch | Directory to monitor |
| `7` | Git tree | Provider, repository URL, branch, output format, output |
| `8` | Library | Action and its required inputs; purge asks for `PURGE` |
| `9` | Credentials | Store/clear, target, username; store then asks for a masked token |
| `10` | Security | Action and the file/base/candidate fields that action needs |
| `11` | Version | Prints the local version |
| `0`, `exit`, `quit` | Exit | Closes the interactive menu |

The menu is a shortcut. Use typed commands for options it does not ask for:
presets, sync/deletion, exclusions, anonymous API access, custom watch intervals,
and other advanced settings. `detection` has no numbered menu item.

## All 12 commands

| Command | What it does | Typical use | Changes project files? |
| --- | --- | --- | --- |
| `import` | Reads and converts a structure description | Convert YAML to a reusable tree-symbol file | Writes the chosen output, not the described project |
| `export` | Scans a live directory and writes its layout | Produce a tree diagram or JSON inventory | Writes the chosen output |
| `scaffold` | Creates a project from a description or preset | Generate a new project layout | Yes, unless `--dry-run` |
| `verify` | Compares live paths/types with a description | Find missing/extra entries; optionally synchronize | Only with `--sync` |
| `merge` | Combines two descriptions | Assemble a shared base and project additions | Writes the chosen output |
| `watch` | Reports layout changes or structural drift | Monitor a directory during development | No project mutations |
| `gittree` | Retrieves repository tree metadata over HTTPS | Export a public/private GitHub/GitLab layout | Writes the chosen output; does not clone |
| `auth` | Stores/clears a remote credential | Authenticate private or rate-limited API access | Changes a supported credential store |
| `library` | Manages saved reusable descriptions | Keep and reuse named starter layouts | Changes the PTU library, not the source project |
| `security` | Validates descriptions/names/containment | Check an input before scaffolding | No project mutations |
| `detection` | Provides legacy analysis/merge positional forms | Keep older automation working | BUILD_TREE writes its output |
| `version` | Prints local version or upstream release metadata | Identify the binary and query release information | No update installation |

`help`, `--help`, and `--version` are convenience entry points, not additional
project-operation commands.

## How command syntax works

```text
ptu COMMAND --option VALUE --switch
```

| Syntax | Meaning | Example |
| --- | --- | --- |
| `COMMAND` | One of the 12 commands | `export` |
| `--option VALUE` | An option followed by its value | `--format treesym` |
| `--option=VALUE` | Equivalent equals syntax, with no spaces around `=` | `--format=treesym` |
| `--switch` | A Boolean flag with no following value | `--dry-run` |
| `"path with spaces"` | One argument containing spaces | `--root "E:/Side Projects/app"` |
| `[optional]` in syntax documentation | May be omitted; do not type the brackets | `[--ci]` |
| `A\|B` in a value list | Choose one value; do not type the separator | `skip`, `overwrite`, or `ask` |
| `--` | Ends option parsing; remaining tokens are positional arguments | `ptu import -- --ci dash output.txt` reads a file literally named `--ci` |

Use `--format treesym` or `--format=treesym`. **Do not write
`--format = treesym`**: the standalone `=` is treated as the value.

Switches are `--ci`, `--sync`, `--delete-extras`, `--dry-run`, `--anonymous`,
`--secret-stdin`, `--yes`, and `--check`, where supported. They do not accept
`true`, `false`, or `=true`. Omitting a switch leaves it off.

Command names and regular option keys are case-insensitive. Use the special
help/version spellings shown below exactly. Format names, strategies, display
modes, providers, and preset names should be lowercase as documented. Library,
auth, security, and detection action names accept case variations.

Unknown or duplicate options fail. Prefer fully named options. Positional
arguments occupy fixed slots; they do not automatically fill whichever named
option was omitted. For example, this is wrong:

```text
export --root "E:/app" --format treesym "E:/tree.txt"
```

The unnamed path occupies the `root` positional slot, causing `Specify root
once`. Write `--output "E:/tree.txt"` instead. Positional forms are documented
under each command for compatibility; mixing them with named options is usually
less clear than using named options throughout.

## Global help, version, and CI options

| Entry point / option | Where supported | Meaning |
| --- | --- | --- |
| `--help`, `-h` | Standalone or after a command | Show general or command-specific help; makes no operation changes |
| `help` | Standalone | Show general help |
| `help COMMAND` | Standalone | Show that command's help, e.g. `ptu help export` |
| `--version`, `-V` | Standalone | Equivalent to `ptu version` |
| `--ci` | Any command, before the `--` terminator | Disable interactive secret/overwrite prompting; require complete arguments |

```sh
ptu --help
ptu export --help
ptu help scaffold
ptu --version
ptu export --ci --root ./app --format json --output ./layout.json
```

`--ci` does not stop a long-running watch command. `--overwrite ask` is invalid
in CI. Credential storage in CI needs `--secret-env` or `--secret-stdin`.
Missing required options fail even outside CI; typed commands do not launch a
wizard to fill missing fields. No-argument terminal execution opens the menu;
no-argument redirected execution prints help; no-argument CI execution fails.

## Formats: all input and output types

### What does `--format` mean?

It selects the **representation of a structure**, not the programming language,
project framework, file extension, or directory being scanned.

| Command | Meaning of its format option |
| --- | --- |
| `import --format` | Format to read from the source structure |
| `import --output-format` | Format to write after conversion |
| `export --format` | Format to write from the scanned live directory |
| `export --output-format` | Alias of export's `--format`; do not supply both |
| `scaffold --format` | Format of `--structure`, not the output project's language |
| `verify --format` | Format of the expected `--structure` |
| `merge --format-a`, `--format-b` | Formats of the two input descriptions |
| `watch --format` | Format of the optional expected `--structure` |
| `gittree --format` | Format to write for remote repository metadata |
| `library --format` | Input format for the `save` action |
| `security --format` | Input format for file-based validation actions |
| `detection` | Input formats are positional values, not named flags |

### Input: six formats, seven accepted names

`importable` is an alias for `dash`, so there are six distinct input formats.

| Input name | What the file looks like | When to use it |
| --- | --- | --- |
| `dash` | `- src/` then `-- main.rs` | Compact hand-written nested layouts, or root-relative `- src/main.rs` |
| `importable` | Same as `dash` | Reading an importable export explicitly |
| `tab` | `src/` then one actual tab before `main.rs` | Descriptions indented with tab characters |
| `space` | `src/` then two spaces before `main.rs` by default | Descriptions indented with spaces; change width with supported `--space-unit` options |
| `treesym` | `├── src/` and `│   └── main.rs` | Reading a tree-symbol diagram produced by PTU |
| `json` | Node objects/arrays with `path`, `isDir`, `content`, etc. | Structured automation and exact seed content |
| `yaml` | Node mappings/sequences with equivalent properties | Readable structured descriptions and multiline content |

Omitting an optional input format attempts detection. `.json` chooses JSON;
`.yaml`/`.yml` choose YAML; other names are inspected for structure syntax.
Flat unindented text can be ambiguous. Supply `--format` when detection fails.
Space indentation defaults to **2**. Only import/scaffold/verify and merge's two
space-unit flags can change it; convert other-width input first before passing it
to commands that do not expose a space-unit flag.

### Output: eight accepted names, seven distinct representations

`dash` and `importable` produce the same representation. All eight names are
accepted for export, import conversion, and remote-tree output.

| Output name | Result | Typical extension | Reusable input? |
| --- | --- | --- | --- |
| `treesym` | Tree diagram using `├──`, `│`, and `└──`, with `/` directory markers | `.txt` | Yes, as `treesym`; explicit metadata is preserved |
| `importable` | Dash layout using root-relative paths and Base64 content directives where needed | `.txt` | Yes, as `dash` or `importable` |
| `dash` | Alias of `importable` | `.txt` | Yes |
| `txt` | Plain names indented with spaces; no connectors/header | `.txt` | Display format; does not preserve seed metadata |
| `md` | Markdown heading plus fenced indented text | `.md` | Display format; not a direct PTU input format |
| `json` | Structured nodes with paths, types, and any explicit seed metadata | `.json` | Yes |
| `yaml` | Structured nodes in YAML | `.yaml` or `.yml` | Yes |
| `summary` | Directory and file counts | `.txt` or console | No |

The format flag controls output. A `.txt` filename does not automatically choose
tree symbols. For example, `--format json --output tree.txt` writes JSON. Choose
matching extensions to make later input detection predictable.

**Summary differs by command:** import prints it to stdout without writing the
output file, but still requires `--output` for compatibility. Export and gittree
write summary text to the chosen output file.

### Compare the three text outputs

`--format treesym`:

```text
├── README.md
└── src/
    └── main.rs
```

`--format importable` or `--format dash`:

```text
- README.md
- src/
- src/main.rs
```

`--format txt`:

```text
README.md
src/
  main.rs
```

Local/remote exports contain **names and types, not existing source file bytes**.
When converting a description that already includes explicit seed content,
treesym/importable/JSON/YAML preserve supported content/template metadata.
See [Formats](FORMATS.md) for all node properties and content directives.

## Depth, filtering, and configuration

### Maximum depth

| Value | Meaning |
| --- | --- |
| `0` | Unlimited scan depth, subject to implementation/path limits |
| `1` | Entries immediately below the root |
| `2` | Root entries and their children |
| `N` | Up to N path components below the root |

Local export/watch use explicit `--max-depth`, otherwise selected configuration,
otherwise **5**. Verify has no `--max-depth` flag: set depth in its configuration.
Remote `gittree` defaults to **0** and applies depth after stripping `--subfolder`.

### Display modes

| `--show-mode` | Export behavior |
| --- | --- |
| `all` | Include files and directories; default |
| `folders` | Include directories only |
| `files` | Include files; JSON/YAML/treesym retain necessary directory ancestors as context and omit unrelated empty directories |

`--show-mode` is an export option. It does not filter verify/watch comparisons.

### Exclusions

Default excluded components are `node_modules`, `dist`, `.git`, `.wrangler`,
`.next`, `.turbo`, `out`, and `build`. Hidden entries otherwise remain included.
CLI `--exclude` is available on export and gittree and adds to these defaults:

```text
--exclude "target,.tools,coverage,generated/assets"
```

Commas or semicolons separate rules. A basename matches path components; a
relative path matches that path and its descendants. Matching is case-insensitive.
Rules are literal: glob patterns and negation are unsupported. There is no flag
to clear built-in exclusions. `--exclude ""` does not disable them.

### Ignore/configuration files

Export, verify, and watch accept `--ignore-file`. Otherwise they select the
first existing file in the live root: `.treeignore`, then `.treerc`.
An explicit missing file is an error. These files are not layered.

```text
# Example .treeignore or external config file
exclude: target, .tools, coverage
maxdepth: 0
showmode: all
```

| Key | Aliases | Values / behavior |
| --- | --- | --- |
| `exclude` | `ignore`, `skip` | Additional comma/semicolon-separated literal rules |
| `maxdepth` | `depth` | Nonnegative integer; 0 unlimited |
| `showmode` | `show` | `all`, `folders`, `files`; affects export |
| `template` | None | Accepted for compatibility; does not automatically select a scaffold preset |

`:` or `=` separates keys and values. Bare lines add exclusions. Blank lines,
hash comments, and semicolon comments are ignored. Unknown keys fail.
Simple basename rules from `.gitignore` are additionally read, even when an
explicit ignore file is selected; complex glob/path/negation rules are skipped.
Gittree does not load these local configuration files. Scaffold applies its input
description directly rather than using scan exclusions.

<!-- command:import -->
## 1. import

**Read, validate, and convert a structure description.** This does not create the
described project and is not the command for scanning a live directory.

```text
ptu import --structure FILE --output FILE [--format FORMAT] [--output-format FORMAT] [--space-unit N] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--structure` | Yes | Existing UTF-8 structure file | Description to read |
| `--output` | Yes | Output file path; existing parent directory | Destination for converted output, except summary |
| `--format` | No | Any input format; default detection | How to parse the source |
| `--output-format` | No | Any of the 8 output names; default `importable` | Representation to produce |
| `--space-unit` | No | Integer 1–16; default `2` | Spaces per indentation level for `space` input |

```sh
ptu import --structure ./layout.yaml --output ./tree.txt --output-format treesym
ptu import --structure ./tree.txt --format treesym --output ./layout.json --output-format json
ptu import --structure ./four-spaces.txt --format space --space-unit 4 --output ./layout.yaml --output-format yaml
ptu import --structure ./layout.json --output ./unused.txt --output-format summary
```

The final example prints counts and does not create `unused.txt`. Other outputs
replace the destination atomically after successful validation; the parent must
exist. Reusable formats preserve declared metadata, not arbitrary presentation.

**Positional order:** `structure format output output-format`.

```sh
ptu import ./layout.txt dash ./layout.json json
```

**Exit:** 0 success; 2 invalid description/options or read/write failure.
<!-- /command:import -->

<!-- command:export -->
## 2. export

**Scan a live directory and save its folder/file layout.** This is the command
for producing a tree diagram of an existing project.

```text
ptu export --root DIRECTORY --format FORMAT --output FILE [--max-depth N] [--show-mode MODE] [--exclude RULES] [--ignore-file FILE] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--root` | Yes | Existing directory | Directory to scan; it is not the output path |
| `--format` | Yes, unless using its alias | Any of the 8 output names; no default | Choose treesym/importable/dash/txt/md/json/yaml/summary |
| `--output` | Yes | File path; parent must exist | File to write; extension alone does not select format |
| `--output-format` | Alternative to `--format` | Same output values | Compatibility alias; supplying both is an error |
| `--max-depth` | No | Nonnegative integer; configuration then `5` | Scan depth; `0` means unlimited |
| `--show-mode` | No | `all`, `folders`, `files`; configuration then `all` | Which entry kinds to export |
| `--exclude` | No | Comma/semicolon-separated rules; no extra CLI rules by default | Add exclusions, e.g. `"target,.tools"` |
| `--ignore-file` | No | Config file path; otherwise root config discovery | Select depth/display/exclusion configuration |

### Tree-symbol export, inside the app

At `ptu>`, enter exactly this, adjusting your paths:

```text
export --root "E:/Side Projects/project-tree-utility" --format treesym --output "C:/Users/Toshin/Downloads/txt.txt" --max-depth 0 --exclude "target,.tools"
```

This writes UTF-8 `├──`, `│`, and `└──` connectors. The exclusion skips Rust
build/toolchain directories. Remove or change it if you want those paths included.
The scanned root is not added as an extra folder/header, so a reusable output
describes its contents directly.

### Other exports

```sh
ptu export --root ./app --format json --output ./layout.json --max-depth 0
ptu export --root ./app --format yaml --output ./layout.yaml
ptu export --root ./app --format importable --output ./layout.txt
ptu export --root ./app --format md --output ./STRUCTURE.md
ptu export --root ./app --format treesym --output ./folders.txt --show-mode folders
ptu export --root ./app --format treesym --output ./files.txt --show-mode files
ptu export --root ./app --format summary --output ./counts.txt
ptu export --root ./app --format treesym --output ./tree.txt --ignore-file ./scan.treeignore
```

In files-only treesym/JSON/YAML output, directory ancestors remain as context.
An incomplete scan fails without committing a successful partial output. Paths,
links/reparse points, permissions, and configured exclusions affect scan validity.
Keep the output outside the scanned root or exclude it to avoid including an old
output file in a later export.

**Positional order:** `root format output max-depth show-mode exclude ignore-file`.

```sh
ptu export ./app treesym ./tree.txt 0 all "target,.tools"
```

**Exit:** 0 complete successful export; 2 invalid input, incomplete scan, or output failure.
<!-- /command:export -->

<!-- command:scaffold -->
## 3. scaffold

**Create a project from a layout or one of three bundled presets.** Files use
explicit seed content when supplied; otherwise preset lookup or empty stubs.

```text
ptu scaffold --structure FILE --target DIRECTORY --project NAME [--format FORMAT] [--space-unit N] [--overwrite POLICY] [--dry-run] [--ci]
ptu scaffold --template PRESET --target DIRECTORY --project NAME [--overwrite POLICY] [--dry-run] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--structure` | One of structure/template | Existing description file | Create the paths described in this file |
| `--template` | One of structure/template | `react-vite`, `hono-worker`, `monorepo-pnpm` | Create a complete bundled preset instead |
| `--target` | Yes | Base directory; missing directories can be created | Parent of the new project |
| `--project` | Yes | One portable directory component | Project folder name; destination is target/project |
| `--format` | No, structure mode only | Input format; default detection | Parse the description; not a language selector |
| `--space-unit` | No | 1–16; default `2` | Space-indented input width |
| `--overwrite` | No | `skip`, `overwrite`, `ask`; default `skip` | Policy for existing files |
| `--dry-run` | No | Switch; off by default | Validate and print the plan without creating files/directories/log |

Choose **exactly one** of structure and template. `--project demo` is valid;
`--project apps/demo` is not. Format/space-unit options do not select or modify
a preset; omit them in template mode.

| Overwrite value | Behavior |
| --- | --- |
| `skip` | Keep existing compatible files; count them as skipped |
| `overwrite` | Replace existing compatible files with resolved seed/stub content |
| `ask` | Ask for each existing file; only `y` means overwrite; requires an interactive terminal and is rejected in CI |

```sh
ptu scaffold --structure ./layout.yaml --target ./projects --project demo --dry-run
ptu scaffold --structure ./layout.yaml --target ./projects --project demo
ptu scaffold --structure ./layout.yaml --target ./projects --project demo --overwrite overwrite --ci
ptu scaffold --template react-vite --target ./projects --project web-app
ptu scaffold --template hono-worker --target ./projects --project api-worker
ptu scaffold --template monorepo-pnpm --target ./projects --project workspace
```

| Preset | Generated starting point | Commands to run afterward, in the generated directory |
| --- | --- | --- |
| `react-vite` | React/TypeScript/Vite app | `npm install`, `npm run typecheck`, `npm run build`, `npm run dev` |
| `hono-worker` | Hono TypeScript Cloudflare Worker | `npm install`, `npm run typecheck`, `npm run build` (Wrangler dry-run), `npm run dev` |
| `monorepo-pnpm` | pnpm workspace with apps/packages directories | Install pnpm, `pnpm install`, add package projects, `pnpm run build`, `pnpm run test` |

Generated presets require Node.js 22.12+; the workspace also needs pnpm. These
shell/npm commands run outside `ptu>`. Scaffold does not install dependencies,
run builds, or deploy. The Hono preset's separate `npm run deploy` is a real
deployment command; its build script is only a dry-run.

Preflight refuses type conflicts, unsafe destinations, and known read-only
overwrite/log targets. Success writes reserved `_creation_log.txt`. Do not
declare that root filename in the input. Runtime failures may leave completed
entries; there is no whole-project rollback. A later verify sees the log as an
extra unless included in the expected layout or excluded through configuration.

**Positional file mode:** `structure format target project`.

```sh
ptu scaffold ./layout.txt dash ./projects demo --dry-run
```

**Exit:** 0 successful plan/execution; 2 invalid plan/options or execution failure.
<!-- /command:scaffold -->

<!-- command:verify -->
## 4. verify

**Compare a live directory with an expected description.** Comparison checks
paths and file/directory types, not file contents, timestamps, or permissions.

```text
ptu verify --live DIRECTORY --structure FILE [--format FORMAT] [--space-unit N] [--ignore-file FILE] [--sync] [--delete-extras] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--live` | Yes | Existing live directory | Tree to compare or synchronize |
| `--structure` | Yes | Expected description file | Intended paths/types and missing-file seed content |
| `--format` | No | Input format; default detection | Parse the expected description |
| `--space-unit` | No | 1–16; default `2` | Space-indented input width |
| `--ignore-file` | No | Config path; otherwise root config discovery | Set exclusions and depth for both expected and actual entries |
| `--sync` | No | Switch; off by default | Create missing directories/files after validation |
| `--delete-extras` | No; requires sync | Switch; off by default | Remove eligible extra files and empty directories |

```sh
ptu verify --live ./demo --structure ./layout.json
ptu verify --live ./demo --structure ./layout.json --ignore-file ./verify.treeignore
ptu verify --live ./demo --structure ./layout.json --sync
ptu verify --live ./demo --structure ./layout.json --sync --delete-extras --ci
```

Without sync this is the read-only preview. Verify has no `--dry-run`,
`--max-depth`, `--exclude`, or `--yes` flag. Put custom depth/exclusions in its
ignore file. To compare every level, set `maxdepth: 0` there; otherwise local
depth defaults to 5. Out-of-scope expected paths do not count as missing.

Sync does not overwrite matched files' bytes. It refuses type conflicts and
incomplete initial scans before mutation. Deletion preserves excluded or
depth-limited descendants and potential move sources; directories are removed
only when empty. Potential moves are not automatically relocated. A final
complete rescan determines the result. There is no additional interactive
deletion confirmation after these explicit flags, and partial runtime changes
are not automatically rolled back.

**Output:** MISSING, EXTRA, TYPE CONFLICT lines and a count summary; sync also
reports created/deleted counts. Remaining protected extras can legitimately
leave exit 1 after sync.

**Positional order:** `live structure format`.

```sh
ptu verify ./demo ./layout.txt dash
```

**Exit:** 0 clean final in-scope layout; 1 drift remains; 2 invalid/incomplete input or execution failure.
<!-- /command:verify -->

<!-- command:merge -->
## 5. merge

**Combine two structure descriptions into one reusable dash layout.** This
merges descriptions, not source directories, file bytes from disk, or Git history.

```text
ptu merge --file-a FILE --file-b FILE --output FILE [--format-a FORMAT] [--format-b FORMAT] [--space-unit-a N] [--space-unit-b N] [--strategy STRATEGY] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--file-a` | Yes | Structure file A | First input |
| `--file-b` | Yes | Structure file B | Second input |
| `--output` | Yes | File path; existing parent | Merged importable dash output |
| `--format-a` | No | Input format; detect A by default | Parse file A |
| `--format-b` | No | Input format; detect B by default | Parse file B |
| `--space-unit-a` | No | 1–16; default `2` | Space width for A |
| `--space-unit-b` | No | 1–16; default `2` | Space width for B |
| `--strategy` | No | `union`, `a_over_b`, `b_over_a`; default `union` | Resolve duplicate paths and metadata |

| Strategy | Behavior |
| --- | --- |
| `union` | Combine compatible entries; reject conflicting types or different explicit content/templates |
| `a_over_b` | Keep A's conflicting type/subtree and metadata; fill metadata absent in A from B |
| `b_over_a` | Keep B's conflicting type/subtree and metadata; fill metadata absent in B from A |

```sh
ptu merge --file-a ./base.json --file-b ./extra.yaml --output ./merged.txt
ptu merge --file-a ./base.txt --format-a dash --file-b ./extra.txt --format-b dash --strategy b_over_a --output ./merged.txt
ptu import --structure ./merged.txt --format dash --output ./merged-tree.txt --output-format treesym
```

Merge has no output-format option: output is always importable dash. Use import
afterward for another representation. Supported content/template metadata is
preserved, with Base64 for explicit content. Failures do not commit a new output.

**Positional order:** `file-a format-a file-b format-b strategy output`.

```sh
ptu merge ./base.txt dash ./extra.yaml yaml union ./merged.txt
```

**Exit:** 0 success; 2 invalid inputs, conflict, or output failure.
<!-- /command:merge -->

<!-- command:watch -->
## 6. watch

**Monitor structural changes, optionally comparing against a fixed description.**
It is a long-running read-only command, not a synchronizer or source-content watcher.

```text
ptu watch --path DIRECTORY [--structure FILE] [--format FORMAT] [--max-depth N] [--ignore-file FILE] [--interval-ms N] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--path` | Yes | Existing directory | Directory to monitor |
| `--structure` | No | Expected description; none by default | Report drift against this layout instead of only changes |
| `--format` | No | Input format; default detection when structure supplied | Parse the expected description |
| `--max-depth` | No | Nonnegative integer; config then `5` | Scan depth; 0 unlimited |
| `--ignore-file` | No | Config path; otherwise root config discovery | Select exclusions/depth |
| `--interval-ms` | No | Integer 100–60000; default `1000` | Milliseconds between complete polling snapshots |

```sh
ptu watch --path ./app
ptu watch --path ./app --structure ./layout.json --max-depth 0 --interval-ms 2000
ptu watch --path ./app --ignore-file ./scan.treeignore --ci
```

Without a structure, changes are relative to the previous complete snapshot.
With one, an initial comparison is printed and changed snapshots report drift.
Content-only edits are ignored. Failed/incomplete snapshots warn and retry rather
than replacing the last valid snapshot. Short-lived changes between polls may
be missed. Increasing interval or narrowing scope reduces scan work.

Press Ctrl+C to stop. In the interactive app this returns to the menu and watch
can be started again. In direct command execution it ends the watch invocation.
CI does not make it finish after one snapshot. There are no `--sync`,
`--delete-extras`, `--show-mode`, or `--space-unit` watch options. Space input uses 2.

**Positional order:** `path structure ignore-file max-depth`; provide format by name.

**Exit:** 0 normal stop; 2 invalid setup/initial scan failure. Periodic scan errors warn and retry.
<!-- /command:watch -->

<!-- command:gittree -->
## 7. gittree

**Retrieve a repository's layout through its provider API.** This exports names
and types. It does not clone the repository, retrieve source bytes, or fetch history.

```text
ptu gittree --provider PROVIDER --repo URL --branch REF --format FORMAT --output FILE [--anonymous] [--subfolder PATH] [--max-depth N] [--exclude RULES] [--gitlab-base URL] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--provider` | Yes | `github` or `gitlab` | Select the API implementation |
| `--repo` | Yes | HTTPS repository URL | Repository to describe |
| `--branch` | Yes | Nonempty branch/ref; no guessed default | Select the repository tree, e.g. `main`, `master`, or a provider-supported ref |
| `--format` | Yes | Any of the 8 output names | Output representation |
| `--output` | Yes | File path; existing parent | Local output file |
| `--anonymous` | No | Switch; off by default | Skip all native-vault and Git-helper credential lookup |
| `--subfolder` | No | Repository-relative folder; default entire tree | Keep descendants and strip the selected prefix from output |
| `--max-depth` | No | Nonnegative integer; default `0` | Depth after subfolder stripping; 0 unlimited |
| `--exclude` | No | Additional literal rules | Filter remote paths, adding to default exclusions |
| `--gitlab-base` | No | HTTPS base; default `https://gitlab.com` | Self-hosted GitLab origin and optional installation prefix |

```sh
ptu gittree --anonymous --provider github --repo https://github.com/octocat/Hello-World --branch master --format treesym --output ./remote-tree.txt
ptu gittree --anonymous --provider gitlab --repo https://gitlab.com/gitlab-examples/nodejs --branch master --format json --output ./remote.json
ptu gittree --provider github --repo https://github.com/owner/private-repo --branch main --subfolder packages/tool --format yaml --output ./tool.yaml
ptu gittree --provider gitlab --repo https://git.example.com/group/repo --gitlab-base https://git.example.com --branch main --format importable --output ./remote.txt
```

The last two URLs are placeholders to replace with repositories you can access.
Omit anonymous mode to use stored credentials; see auth. Without credentials,
public repositories may still work, subject to provider quotas. GitHub must use
`github.com`; GitHub Enterprise is not implemented. GitLab base and repository
must share HTTPS authority; a base prefix must contain the repository namespace.
Use `--provider gitlab` for a self-hosted GitLab server.

Both providers encode branch/path values and reject incomplete/malformed trees.
GitHub truncation fails; GitLab pagination requires sequential metadata and has
a 1000-page bound. Requests verify TLS, refuse redirects, use bounded timeouts
and retries, and cap individual response bodies at 32 MiB. HTTP 403 may mean
permissions or an exhausted rate limit; HTTP 429 means throttling. Never treat
a request failure as an empty successful export. Local ignore files are not loaded.

**Positional order:** `provider repo branch output format subfolder max-depth exclude gitlab-base`.
The positional `output` is before `format`, unlike export. Prefer named options.

**Exit:** 0 nonempty successful export; 1 no matching entries (output is not written
or cleared); 2 URL/input/network/provider/output failure.
<!-- /command:gittree -->

<!-- command:auth -->
## 8. auth

**Store or clear a remote token using a supported credential backend.** It does
not create a provider token or grant repository permissions. Obtain a token with
the necessary provider permissions separately.

```text
ptu auth --action store --target HTTPS_URL [--username NAME] [--secret-env VARIABLE | --secret-stdin] [--ci]
ptu auth --action clear --target HTTPS_URL [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--action` | Yes | `store` or `clear` | Write/update a credential, or remove it |
| `--target` | Yes | HTTPS host/repository target | Credential lookup scope, e.g. `https://github.com` |
| `--username` | No, store metadata | String; default `oauth2` | Stored username/Git-helper field; does not create a separate native-vault entry for the same target |
| `--secret-env` | One secret channel in CI | Environment variable **name**, not its value | Read the token from that process variable |
| `--secret-stdin` | One secret channel in CI | Switch | Read one token line from standard input |

### Store interactively

```sh
ptu auth --action store --target https://github.com
```

The app asks for a masked token. This works from the menu or a terminal. Running
store again for the same native target replaces its existing token. A host target
can serve repositories on that host; use an exact repository target for narrower
lookup scope. Targets reject embedded username/password, query, and fragment.

### Store in automation

Assuming a secret manager has supplied the process variable `GITHUB_TOKEN`:

```sh
ptu auth --ci --action store --target https://github.com --secret-env GITHUB_TOKEN
```

Do not write `--secret-env "$GITHUB_TOKEN"`: the option takes the variable name.
Do not pass the token as a positional argument or a `--token` flag; no such flag
exists. Choose one channel, not both. Empty tokens, tokens above 16 KiB, and
CR/LF/NUL inside the token fail; a native backend may impose tighter storage limits.

PowerShell stdin example, outside `ptu>`, with a provisioned environment variable:

```powershell
$env:GITHUB_TOKEN | .\ptu.exe auth --ci --action store --target https://github.com --secret-stdin
```

Stdin reads one line and removes its line ending. Without a channel, store needs
a terminal and uses the masked prompt; CI/nonterminal storage otherwise fails.

### Clear

```sh
ptu auth --action clear --target https://github.com
```

Clear is idempotent for an absent native record. It rejects secret-channel flags.
Windows uses Credential Manager; macOS uses Keychain. Linux/Termux use configured
Git credential helpers and require a compatible secure helper for persistence.
The standard plaintext `store` helper is rejected for storing. There is no
automatic plaintext fallback. Existing legacy vault identities are not migrated
implicitly. See [Operations](OPERATIONS.md#credentials-and-http) for lookup details.

**Positional order:** `action target username`.

**Exit:** 0 successful store/clear; 2 invalid input, missing secret, or backend failure.
<!-- /command:auth -->

<!-- command:library -->
## 9. library

**Save and manage reusable structure descriptions by name or ID.** The Rust
library is independent of legacy data and lives in its per-user data directory,
or the directory specified by `PTU_DATA_DIR`.

```text
ptu library --action ACTION [action-specific options] [--ci]
```

| Option | Used by | Values / default | Purpose |
| --- | --- | --- | --- |
| `--action` | All actions | `save`, `list`, `open`, `rename`, `delete`, `purge` | Operation to perform; may instead be the first positional word |
| `--file` | save | Required existing structure file | Description to parse and save |
| `--format` | save | Input format; default detection | Format of that file; space indentation uses 2 |
| `--source` | save | Free-text label; default `manual` | Provenance metadata; not a filename or download URL to fetch |
| `--name` | save/open/rename/delete | Required name; existing ID also accepted for lookup actions | New saved name or existing record to operate on |
| `--new-name` | rename | Required new name | Replacement display name |
| `--yes` | purge | Required switch | Explicitly authorize clearing current managed records |

### Every library action

| Action | Required inputs | Result |
| --- | --- | --- |
| `save` | file, name | Save normalized structure/metadata; print the final unique name |
| `list` | None | Print ID, name, entry count, and source as a table |
| `open` | name or ID | Materialize an importable dash view; print its absolute path |
| `rename` | name/ID, new-name | Change the saved name |
| `delete` | name/ID | Delete that record and its managed materialized view |
| `purge` | `--yes` | Clear all current managed records/views |

```sh
ptu library --action save --file ./layout.yaml --name starter --source team
ptu library --action list
ptu library --action open --name starter
ptu library --action rename --name starter --new-name starter-v2
ptu library --action delete --name starter-v2
ptu library --action purge --yes
```

Open does not launch an editor or a scaffold operation. Use the printed path as
the structure for import/scaffold/verify. Listing is a table, not JSON; `--format`
does not select list output. Save stores the description's normalized entries and
seed metadata, not the original file's presentation or the project's source bytes.

Names are 1–200 UTF-8 bytes, nonblank, without control characters; ASCII-digits-only
names are reserved for ID lookup. Unicode lowercase matching is consistent for
save/load/lookup/rename. Duplicate saves receive suffixes such as `starter-2`;
rename refuses another existing name. Pure IDs such as `1` can select records.

Operations lock the library with a five-second acquisition bound and atomically
replace one authoritative snapshot. Corrupt state is preserved and rejected,
not reset. The previous snapshot can remain in `library.json.bak`; purge is not
secure erasure of backup history. See [Operations](OPERATIONS.md#library-storage).

**All positional forms:**

```sh
ptu library list
ptu library save ./layout.txt dash manual starter
ptu library open starter
ptu library rename starter starter-v2
ptu library delete starter-v2
ptu library purge --yes
```

Save positional order is `file format source name`. Prefer named save options
when omitting format/source. Do not combine positional and named action values.

**Exit:** 0 success; 1 missing record for open/rename/delete; 2 invalid action,
missing confirmation, malformed file/index, lock timeout, or I/O failure.
<!-- /command:library -->

<!-- command:security -->
## 10. security

**Validate a description or destination containment without creating a project.**
These checks are not a malware scanner or an operating-system sandbox.

```text
ptu security --action ACTION [--file FILE] [--format FORMAT] [--base DIRECTORY] [--candidate PATH] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--action` | Yes | `VALIDATE_FILE`, `VALIDATE_NAMES`, `VALIDATE_ALL`, `VALIDATE_PATH` | Select the check; first positional action also supported |
| `--file` | File-based actions | Existing description file | Structure to parse and validate |
| `--format` | No | Input format; default detection | Parse the description; space width fixed at 2 |
| `--base` | ALL and PATH | Destination base directory path | Boundary for resolved destinations |
| `--candidate` | PATH | Path to test, resolved from caller cwd | Candidate destination; not a path implicitly relative to base |

| Action | Required fields | What is checked |
| --- | --- | --- |
| `VALIDATE_FILE` | file | Full supported schema, hierarchy, metadata, and portable names |
| `VALIDATE_NAMES` | file | The same parser/name validation as VALIDATE_FILE in this edition |
| `VALIDATE_ALL` | file, base | File validation plus resolving each entry under base and checking existing ancestors |
| `VALIDATE_PATH` | candidate, base | Candidate is contained in base and its existing ancestors are not links/reparse points |

```sh
ptu security --action VALIDATE_FILE --file ./layout.json
ptu security --action VALIDATE_NAMES --file ./tree.txt --format treesym
ptu security --action VALIDATE_ALL --file ./layout.yaml --base ./projects/demo
ptu security --action VALIDATE_PATH --candidate ./projects/demo/src --base ./projects/demo
```

Names use portable Windows-compatible rules on all systems. Absolute paths,
traversal components, reserved device names, streams, invalid characters, and
other invalid structure names fail. Candidate/base CLI paths may be absolute or
relative; layout entries themselves must remain relative. ALL is not a full
scaffold dry-run and does not guarantee later write permission or prevent races
from other processes changing the filesystem.

**Positional forms:** `ACTION file format base` for file actions, or
`VALIDATE_PATH candidate base` for path checking.

```sh
ptu security VALIDATE_FILE ./layout.txt dash
ptu security VALIDATE_NAMES ./layout.yaml yaml
ptu security VALIDATE_ALL ./layout.txt dash ./projects/demo
ptu security VALIDATE_PATH ./projects/demo/src ./projects/demo
```

**Exit:** 0 passed; 1 rejected VALIDATE_PATH containment/ancestor check;
2 malformed input, missing fields, invalid action, or file/ALL validation failure.
<!-- /command:security -->

<!-- command:detection -->
## 11. detection

**Legacy positional compatibility adapter.** New automation should normally use
import and merge directly. The action name is British-spelled `ANALYSE`.

```text
ptu detection ANALYSE FILE FORMAT [--ci]
ptu detection BUILD_TREE FILE_A FORMAT_A FILE_B FORMAT_B STRATEGY OUTPUT [--ci]
```

| Action | Arguments in exact order | Behavior |
| --- | --- | --- |
| `ANALYSE` | file, input format | Validate the description and print directory/file counts |
| `BUILD_TREE` | file-a, format-a, file-b, format-b, strategy, output | Merge the inputs into importable dash |

These are positional-only commands. There are **no command-specific named
options**; only global CI/help handling is available. Input format names are the
seven accepted input names; strategies are union/a_over_b/b_over_a. Space input
uses width 2 here. Use import/merge for configurable space widths or named paths.

```sh
ptu detection ANALYSE ./layout.txt dash
ptu detection BUILD_TREE ./base.txt dash ./extra.yaml yaml union ./merged.txt
```

ANALYSE prints summary text without a project mutation. BUILD_TREE requires an
existing output parent. It does not build or compile an application.

**Exit:** 0 success; 2 malformed action/argument count, invalid descriptions,
merge conflict, or output failure.
<!-- /command:detection -->

<!-- command:version -->
## 12. version

**Print the running executable's version; optionally query upstream release metadata.**

```text
ptu version [--check] [--ci]
```

| Option | Required? | Values / default | Purpose |
| --- | --- | --- | --- |
| `--check` | No | Switch; off by default | Query the upstream GitHub latest published release tag |

```sh
ptu version
ptu --version
ptu -V
ptu version --check
```

`--check-update` and `--checkupdate` are compatibility aliases of `--check`.
The upstream endpoint is
`https://api.github.com/repos/tanvirfoysal99/project-tree-utility/releases/latest`.
This prints metadata, not a semantic-version upgrade decision, and never
downloads/installs/executes an update. The upstream may contain legacy releases.
No published release (404) is reported as no available comparison, with exit 0.
Other network/API failures, including rate limiting, remain errors.

**Positional arguments:** none.

**Exit:** 0 local version / successful lookup / no published release;
2 unexpected API response or request failure.
<!-- /command:version -->

## Option lookup by purpose

This index is a map to the command tables above, not a claim that every option
works with every command. Unsupported combinations fail as unknown options.

| Option or group | Commands that accept it | Meaning |
| --- | --- | --- |
| `--root` | export | Live directory to scan |
| `--live` | verify | Live directory to compare/change |
| `--path` | watch | Live directory to monitor |
| `--structure` | import, scaffold, verify, watch | Layout description to read |
| `--file` | library, security | Input description for the relevant action |
| `--file-a`, `--file-b` | merge | First/second input description |
| `--format` | import, export, scaffold, verify, watch, gittree, library, security | Input or output representation according to command |
| `--output-format` | import, export | Conversion output selector, or export alias |
| `--format-a`, `--format-b` | merge | Input representations |
| `--space-unit` | import, scaffold, verify | Width of space indentation |
| `--space-unit-a`, `--space-unit-b` | merge | Width for each input |
| `--output` | import, export, merge, gittree | Output file |
| `--max-depth` | export, watch, gittree | Depth limit; 0 unlimited |
| `--show-mode` | export | all/folders/files output filter |
| `--exclude` | export, gittree | Additional literal exclusion rules |
| `--ignore-file` | export, verify, watch | Local scope configuration |
| `--target` | scaffold, auth | Project base directory, or HTTPS credential target respectively |
| `--project`, `--template`, `--overwrite`, `--dry-run` | scaffold | Creation destination/preset/policy/preview |
| `--sync`, `--delete-extras` | verify | Opt-in creation/deletion during comparison |
| `--strategy` | merge | union/a_over_b/b_over_a conflict policy |
| `--interval-ms` | watch | Polling interval |
| `--provider`, `--repo`, `--branch`, `--subfolder`, `--gitlab-base`, `--anonymous` | gittree | Remote API selection/scope/authentication mode |
| `--action` | auth, library, security | Command-specific sub-action |
| `--username`, `--secret-env`, `--secret-stdin` | auth | Credential metadata and secret transport |
| `--source`, `--name`, `--new-name`, `--yes` | library | Library metadata, identity, rename, purge authorization |
| `--base`, `--candidate` | security | Containment boundary and candidate |
| `--check` | version | Upstream release metadata lookup |

## Compatibility aliases

Canonical names use two hyphens. Legacy one-hyphen PowerShell-style keys and
case variations are accepted where their canonical option is valid. These are
the additional renamed keys supported by the parser:

| Alias | Canonical option |
| --- | --- |
| `-StructureFile` | `--structure` |
| `-LivePath` | `--live` |
| `-RootPath` | `--root` |
| `-OutputFile` | `--output` |
| `-OutputFormat` | `--output-format` |
| `-TargetBase` | `--target` |
| `-ProjectName` | `--project` |
| `-TemplateName` | `--template` |
| `-OverwriteMode` | `--overwrite` |
| `-DryRun` | `--dry-run` |
| `-IgnoreFile` | `--ignore-file` |
| `-MaxDepth` | `--max-depth` |
| `-ShowMode` | `--show-mode` |
| `-ExtraExclude`, `-ExcludeList` | `--exclude` |
| `-SpaceUnit` | `--space-unit` |
| `-DeleteExtras` | `--delete-extras` |
| `-FileA`, `-FileB` | `--file-a`, `--file-b` |
| `-FormatA`, `-FormatB` | `--format-a`, `--format-b` |
| `-SpaceUnitA`, `-SpaceUnitB` | `--space-unit-a`, `--space-unit-b` |
| `-RepoUrl` | `--repo` |
| `-GitLabBaseUrl` | `--gitlab-base` |
| `--check-update`, `--checkupdate` | `--check` |
| `-Ci` | Global `--ci` |

Aliases are not extra capabilities: `-MaxDepth` still does not work on verify,
and `-OutputFormat` still does not work on gittree. Use canonical names for new scripts.

## Environment variables

Set variables in your operating-system shell, not at `ptu>`.

| Variable | Runtime effect |
| --- | --- |
| `TREE_CI` | `1`, `true`, or `yes` (case-insensitive) enable CI behavior; other values do not |
| `PTU_DATA_DIR` | Override the per-user Rust library location; relative values resolve from cwd |
| A variable named by `--secret-env` | Provides that auth invocation's token; the name is user-selected |

```powershell
$env:PTU_DATA_DIR = 'E:/PTU-library'
.\ptu.exe library list
Remove-Item Env:\PTU_DATA_DIR
```

```sh
PTU_DATA_DIR="$HOME/.local/share/my-ptu-library" ptu library list
TREE_CI=1 ptu export --root ./app --format json --output ./layout.json
```

The application does not automatically consume `GITHUB_TOKEN`/`GITLAB_TOKEN` for
gittree. Use auth's `--secret-env` to store a token, then omit `--anonymous` for
lookup. Test-only `PTU_TEST_BINARY` is documented in [Tests](../tests/README.md),
not a runtime configuration option.

## Exit codes and automation

| Code | Meaning | Commands with a normal code-1 result |
| --- | --- | --- |
| `0` | Success | All commands |
| `1` | Negative result, not a parser failure | verify drift; missing library record; rejected VALIDATE_PATH; no matching remote entries |
| `2` | Invalid options/input or execution failure | All commands |

PowerShell: inspect `$LASTEXITCODE` immediately after PTU. CMD: use `%ERRORLEVEL%`.
POSIX shells: inspect `$?` immediately. Another command can overwrite the status.

```powershell
.\ptu.exe verify --ci --live ./app --structure ./layout.json
$result = $LASTEXITCODE
if ($result -eq 1) { Write-Output 'Structural drift found' }
elseif ($result -eq 2) { throw 'Verification could not complete' }
```

For predictable automation use named options, `--ci`, explicit formats/depth,
an intentional output location, and appropriate exit handling. Do not assume
every nonzero result means the same thing, or that `--ci` makes watch finite.

## Errors and corrections

| Message / symptom | Meaning | Correction |
| --- | --- | --- |
| `Specify root once` | Unnamed output was interpreted as another root positional argument | Add `--output` before the destination; use fully named options |
| `Required option: --output` | Destination is missing | Supply a path whose parent already exists |
| `Unsupported format` | Wrong format name, uppercase value, or an old executable | Use the lowercase table value; reopen the current binary; update an extracted portable copy |
| `Unknown option` | Flag belongs to another command, or does not exist | Check that command's table; for verify depth use an ignore file |
| `Ambiguous structure` | Flat text does not identify its indentation scheme | Specify `--format dash/tab/space/treesym` explicitly |
| JSON error on a tree diagram | `.json` selected JSON parsing for non-JSON text | Use a matching extension or explicit `--format treesym` |
| Output-parent error | Tool does not create export/conversion parent folders | Create the output directory in your shell first |
| Incomplete scan/link refusal | Scoped tree contains inaccessible/unsupported paths or links/reparse points | Resolve access or exclude the relevant subtree; do not interpret failure as a partial successful export |
| Extra `_creation_log.txt` after scaffold | Scaffold's own log is not in the expected layout | Use an external ignore file excluding that filename |
| Sync still exits 1 | Protected extras/move sources remain | Inspect the report; sync does not automatically move files or delete protected descendants |
| HTTP 403 / 429 | Provider permissions/policy or rate limiting | Check access/quota; use an appropriate stored token when needed; do not repeatedly retry an exhausted quota |
| No published upstream release | Latest-release lookup returned no available release | No update comparison is available; it is not a download failure |
| Library index error / busy | Invalid snapshot or lock timeout | Preserve data, stop competing writers, inspect backup/recovery instructions |
| Typed command fails in an old open window | That process still runs the old executable code | Close it and reopen the updated `ptu.exe` |

Descriptions and scans are limited to supported portable names and structure
complexity. Source inputs/configs and library snapshots are limited to 8 MiB;
normalized layouts/scans to 100,000 entries and 128 path components; components
to 255 UTF-16 code units. Host filesystem limits can be stricter. Review
[Formats](FORMATS.md), [Operations](OPERATIONS.md), and [Security](SECURITY.md)
for schema, recovery, and mutation boundaries.
