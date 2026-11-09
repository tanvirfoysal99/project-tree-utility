# Getting started: where to type and what to run

Start here if this is your first time using Project Tree Utility. For every
command, option, default, accepted value, and exit code, use the
[complete CLI reference](CLI.md).

## 1. Start the correct executable

| What you have | How to start it |
| --- | --- |
| Extracted portable Windows ZIP | Double-click `ptu.exe`, or open a terminal in that folder and run `.\ptu.exe` in PowerShell / `ptu.exe` in CMD |
| This repository's Rust source | In `release/`, build with `cargo build --release --locked`, then run `.\target\release\ptu.exe` |
| Compatible Linux/macOS/Termux executable | In its folder, run `./ptu` |
| Installed command on PATH | Run `ptu` from your shell |

Windows portable users do not need Rust. Linux/macOS/Termux need binaries built
for their own environment; a Windows `.exe` is not their native command. See
[Installation](INSTALLATION.md) for building/installing and platform validation.

When replacing a portable executable, close old PTU windows and start the new
copy. An already-running window continues to use its old code.

## 2. Recognize the two prompts

### Inside the application

If you see `ptu>`, you are already inside PTU. Type a command **without** `ptu.exe`:

```text
help
```

```text
export --help
```

```text
export --root "E:/Projects/my-app" --format treesym --output "E:/Projects/tree.txt" --max-depth 0
```

You can also enter `2` for export and answer the prompts. Enter `treesym` when
asked for the format. Type `exit` or `0` to close the app. Do not type the `ptu>`
prefix itself.

### In PowerShell or CMD

In an operating-system terminal, launch the executable as part of the command:

```powershell
.\ptu.exe export --root "E:/Projects/my-app" --format treesym --output "E:/Projects/tree.txt" --max-depth 0
```

CMD can use `ptu.exe` instead of `.\ptu.exe`. On Linux/macOS/Termux use `./ptu`
from the executable directory, or `ptu` once installed on PATH.

Commands such as `cd`, `New-Item`, shell variables, and pipelines belong in this
operating-system terminal. They are not PTU commands inside `ptu>`.

## 3. Export an existing directory as a tree diagram

At `ptu>`, use this example with your own source and destination:

```text
export --root "E:/Side Projects/project-tree-utility" --format treesym --output "C:/Users/Toshin/Downloads/txt.txt" --max-depth 0 --exclude "target,.tools"
```

| Part | What to change / what it means |
| --- | --- |
| `export` | Scan an existing directory |
| `--root "E:/Side Projects/project-tree-utility"` | Source directory; replace it with the directory you want described |
| `--format treesym` | Write `├──`, `│`, and `└──` tree-symbol connectors |
| `--output "C:/Users/Toshin/Downloads/txt.txt"` | Destination file; its parent directory must exist |
| `--max-depth 0` | Include all depth levels, subject to scope and implementation limits |
| `--exclude "target,.tools"` | Omit Rust build/toolchain directories; change these rules for your project |

Use forward slashes and quote paths containing spaces. Existing output files
are replaced after successful export unless read-only or otherwise invalid.
The source is scanned, not copied or modified. Exports contain names/types,
not source file contents. Hidden entries are included; built-in exclusions and
explicit rules still apply.

Success reports `Exported N entries`. Open the destination file in an editor.
The tree itself is saved there rather than printed after that message:

```text
├── README.md
└── src/
    └── main.rs
```

In a Windows terminal outside PTU, `notepad "C:/Users/Toshin/Downloads/txt.txt"`
can open the saved file. In Explorer, opening the file normally also works.

## 4. Choose an output format

| You want | Use | Suggested destination |
| --- | --- | --- |
| A tree diagram | `--format treesym` | `tree.txt` |
| A reusable dash layout | `--format importable` (or `dash`) | `layout.txt` |
| Plain indented names | `--format txt` | `structure.txt` |
| A Markdown document | `--format md` | `STRUCTURE.md` |
| Structured automation data | `--format json` | `layout.json` |
| Structured YAML | `--format yaml` | `layout.yaml` |
| Only file/directory counts | `--format summary` | `counts.txt` |

These are **8 accepted names** for 7 distinct output representations because
dash/importable are aliases. A `.txt` filename alone does not select a diagram;
you still need `--format treesym`. Input formats are a separate list: dash,
tab, space, treesym, JSON, YAML, with importable accepted as a dash alias.

## 5. Show folders, files, or a limited depth

At `ptu>`:

```text
export --root "E:/Projects/my-app" --format treesym --output "E:/Projects/folders.txt" --show-mode folders --max-depth 2
```

`--show-mode` accepts `all`, `folders`, or `files`. Files-only tree output keeps
directory ancestors so filenames remain attached to the right paths.
Depth 1 means immediate entries; depth 2 includes their children; 0 is unlimited.
The local default is 5 unless configuration overrides it.

## 6. Convert a description instead of scanning a directory

Use import for an existing description file:

```text
import --structure "E:/Projects/layout.yaml" --output "E:/Projects/tree.txt" --output-format treesym
```

If reading a tree-symbol file whose format is not detected, specify it:

```text
import --structure "E:/Projects/tree.txt" --format treesym --output "E:/Projects/layout.json" --output-format json
```

Here `--format` describes the input and `--output-format` describes the result.
This command does not scan the paths named inside the description.

## 7. Try scaffold and verify using included examples

Run this walkthrough from the standalone Rust directory (`release/` in the
original repository) or the extracted portable package. Both include `examples/`.
For a source checkout, open the built executable from that working directory.

At `ptu>`, first preview:

```text
scaffold --structure ./examples/layout.txt --format dash --target ./demo-work --project demo --dry-run
```

Create the project after reviewing the plan:

```text
scaffold --structure ./examples/layout.txt --format dash --target ./demo-work --project demo
```

The result is `demo-work/demo`. PTU also creates `_creation_log.txt`. The included
external ignore file excludes that generated log for this comparison:

```text
verify --live ./demo-work/demo --structure ./examples/layout.txt --format dash --ignore-file ./examples/verify.treeignore
```

Export the demo as a diagram:

```text
export --root ./demo-work/demo --format treesym --output ./demo-tree.txt --max-depth 0 --exclude _creation_log.txt
```

Verify's clean result means names/types match. It does not compare file bytes.
To create missing entries later, add `--sync`. Extra-file deletion additionally
requires `--delete-extras`; read [the verify reference](CLI.md#4-verify) before
using it on valuable data. Verify without sync is the read-only preview.

## 8. Find the other commands

There are **12 public commands**, all documented in the
[complete reference](CLI.md#all-12-commands):

| Task | Command |
| --- | --- |
| Convert a description | `import` |
| Scan/export a directory | `export` |
| Create a project | `scaffold` |
| Compare/synchronize layout | `verify` |
| Combine descriptions | `merge` |
| Monitor layout changes | `watch` |
| Read a GitHub/GitLab layout | `gittree` |
| Store/clear provider tokens | `auth` |
| Manage saved descriptions | `library` |
| Validate descriptions/paths | `security` |
| Run legacy positional analysis/merge | `detection` |
| Identify binary/query release metadata | `version` |

At `ptu>`, type `COMMAND --help`, such as `scaffold --help`. Outside the app,
run `.\ptu.exe COMMAND --help` or `ptu COMMAND --help` as appropriate. The
[full command tables](CLI.md) explain each flag instead of only listing its name.

## Common mistakes

| Mistake | Correct form |
| --- | --- |
| Omitting the output flag | `--output "E:/tree.txt"`, not a loose path after named options |
| Writing `--format = treesym` | `--format treesym` or `--format=treesym` |
| Expecting `.txt` to mean tree symbols | Explicitly use `--format treesym` |
| Typing `.\ptu.exe ...` inside `ptu>` | Start with the command, e.g. `export ...` |
| Typing PowerShell commands inside PTU | Exit PTU and use your operating-system terminal |
| Assuming unlimited depth by default | Supply `--max-depth 0` on export/watch, or set verify's config depth |
| Using verify's nonexistent `--dry-run` | Run verify without `--sync` for a read-only comparison |
| Trying a feature in an old open executable | Close that window and reopen the updated binary |

For all options, aliases, action lists, limits, and error meanings, use
[Complete CLI reference](CLI.md).
