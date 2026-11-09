# Operations and recovery

## Scan configuration

Local export, verify, and watch share scope rules. Defaults exclude directory/path
components named `node_modules`, `dist`, `.git`, `.wrangler`, `.next`, `.turbo`,
`out`, and `build`. Exclusions also apply to expected comparison entries.

The explicit `--ignore-file` wins; otherwise `.treeignore`, then `.treerc`, is
selected from the scanned root. Files are not layered. Missing explicit files
and malformed configuration fail.

```text
# Extra exclusions
exclude: coverage, cache, generated/assets
maxdepth: 0
showmode: all
```

Keys accept `:` or `=`. Exclusion aliases: `exclude`, `ignore`, `skip`; depth:
`maxdepth`, `depth`; display: `showmode`, `show`. Bare lines add exclusions.
Comma/semicolon delimit lists. Blank lines and leading hash/semicolon comments
are ignored. `template` is accepted but does not choose a scaffold preset.
Unknown keys fail. Simple basename rules from `.gitignore` also add exclusions;
wildcards, paths, and negations are not interpreted.

Basename exclusions match components; path exclusions match that path and its
descendants. Matching is case-insensitive for portability. This is not gitignore
glob syntax. Depth counts components below the root; zero is unlimited.
Explicit export/watch options override configuration, then defaults apply.

## Mutation model

Scaffold checks all destination paths and content/template resolution before
creating the project. It writes declared files and `_creation_log.txt`.
Existing files are skipped by default. Overwrite atomically replaces each file.
New files use exclusive creation. No preset runs external commands automatically.

Verify compares layout only. Sync creates missing entries but preserves matched
bytes. Type conflicts require manual resolution. Deletion additionally requires
`--delete-extras`; extra directories are removed only when empty. Exclusions and
depth-limited descendants remain protected. Potential move sources (matching
missing-entry basenames and types), their descendants, and ancestors are kept.
This may leave drift intentionally. A fresh scan determines final success.

Individual replacement files are staged beside their destinations, flushed, and
atomically committed. This does not provide all-or-nothing project mutation.
Disk-full errors, permissions changes, interruptions, and concurrent filesystem
changes may leave completed operations. Resolve the reported cause, inspect the
tree, and rerun verify before retrying sync.

## Library storage

Default data locations follow the platform's per-user application data directory
for `project-tree-utility`. Set `PTU_DATA_DIR` to explicitly select a directory.
Neither legacy root data nor existing legacy credentials are migrated implicitly.

| File | Purpose |
| --- | --- |
| `library.json` | Authoritative versioned snapshot including saved layout metadata |
| `library.json.bak` | Previous snapshot, replaced before a subsequent commit |
| `library.lock` | Exclusive access lock with a five-second acquisition bound |
| `tree-<id>.txt` | Derived importable view materialized by `library open` |

A single snapshot avoids cross-file index/content commits. Every load validates
schema, IDs, names, and normalized entries. Invalid state is preserved and causes
failure; it is never silently reset. A crash can leave an obsolete derived export,
but it cannot make that export authoritative. Use `open` to regenerate views.
Backups may retain previously deleted layout content; purge clears current records
but is not secure erasure and does not erase backup history.

To recover: stop all instances, copy the damaged index and backup somewhere safe,
inspect both, and restore a known-good snapshot manually. Do not replace the index
with an empty file. Saved structures can contain seed file content; treat library
directories and backups as project data, not secret vaults.

## Credentials and HTTP

Windows uses Credential Manager; macOS uses Keychain. The Rust vault entries use
their own keyring identity and need re-provisioning when migrating from legacy.
Linux/Termux use the user's configured Git credential helper. Use a secure helper
and evaluate its persistence policy; terminal-only hosts may have no secure vault.
Store rejects the standard plaintext `store` helper. Helper processes are
noninteractive and limited to ten seconds. Tokens are not printed or accepted
as literal CLI arguments. Lookup tries repository and host contexts.

Requests require HTTPS and validated repository URLs, verify TLS, refuse
redirects, and use twenty-second request/ten-second connection timeouts.
Connection failures, HTTP 429, and server errors have at most three attempts
with short bounded delays. Each JSON response is limited to 32 MiB. GitHub
truncation is refused. GitLab pagination requires sequential `x-next-page`
metadata and is limited to 1,000 pages. HTTP failure is not an empty layout.

## Monitoring

Watch polls every second by default. It reports an initial comparison when a
structure is supplied, then only changed complete snapshots. Filesystem access
errors produce warnings and retry; they never replace the last valid snapshot.
It ignores content-only changes and never mutates the tree. Polling can miss
short-lived changes and costs a full scoped scan per interval. Increase the
interval or narrow scope for large trees. Ctrl+C requests shutdown; its normal
latency is about 100 ms plus any in-progress filesystem scan.
