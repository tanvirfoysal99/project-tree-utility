# Migrating from PowerShell/Batch

The Rust edition is a separate application inside this directory. Existing root
scripts, docs, tests, data, and launchers remain unchanged. Build and validate the
Rust version before changing an existing automation's executable.

## Retained interfaces

Public command names, primary long options, legacy PowerShell option aliases,
documented positional forms, CI mode, and reusable layout formats are retained.
Dash content directives and JSON/YAML metadata round-trip. Native CLI arguments
are passed directly, without Batch-to-PowerShell routing.

## Deliberate changes

| Area | Rust edition |
| --- | --- |
| Entry point | `ptu` / `ptu.exe`, not `tree.bat` |
| Interactive mode | Numbered guided menu and command prompt; no legacy Batch dialogs |
| Missing command options | Error instead of partial interactive prompting |
| Option syntax | Also accepts `--name=value` and standard help/version flags |
| Library | Per-user `library.json` snapshot, independent of legacy data |
| Library open | Materializes a reusable dash view, then prints its path |
| Credentials | Re-provision in Rust vault identities; Git helpers on Linux/Termux |
| YAML | Maintained parser supports more YAML syntax; tags/anchors/aliases refused |
| Case | Portable duplicate rejection; native filesystem case comparison |
| Watch | Configurable polling rather than Windows event subscriptions |
| Merge failure | Consistent exit 2 for invalid/conflicting input |
| Version lookup | GitHub latest release metadata; no implicit update |
| Empty layout | Empty JSON/YAML arrays supported; scaffold rejects empty plans |
| Stub content | Unspecified files are empty unless a preset file matches |

Portable names are enforced on every OS. Consequently Linux/macOS layouts with
names that cannot safely travel to Windows may fail to export. Unix filenames
with non-UTF-8 bytes are unsupported. Symbolic-link/reparse-point traversal is
intentionally refused.

## Transition checklist

1. Build the Rust binary and run its tests.
2. Convert representative legacy inputs with `ptu import`; compare normalized
   reusable output, not display decoration.
3. Export and verify disposable project copies before using sync on working trees.
4. Save legacy structures into the new library using `library save`. No automatic
   index migration touches legacy data.
5. Re-provision required credentials using stdin/environment secret channels.
6. Update automation entry points and account for documented exit-code changes.
7. Validate native builds on every platform you plan to distribute.

This is a functional migration with explicit behavior differences, not a claim
of byte-for-byte reproduction of all legacy menus, logs, reports, or heuristics.
The original PowerShell suite is not executed against Rust automatically; the
Rust suite independently tests its documented contract.
