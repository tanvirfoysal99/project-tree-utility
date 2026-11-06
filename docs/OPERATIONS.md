# Operation and recovery guide

See [commands](CLI.md) for runnable options and [formats](FORMATS.md) for input.

## Scan configuration

Export, verify, and watch share scan and comparison helpers. Hidden entries are
included. Junctions and other reparse points are not traversed; access failures
and unsupported scan entries make a snapshot incomplete.

By default, local scans exclude these directory names:
`node_modules,dist,.git,.wrangler,.next,.turbo,out,build`.

Configuration comes from an explicitly supplied ignore file, or the first
existing file among `.treeignore` and `.treerc` in the scanned root.
A missing explicitly supplied file is an error. Files are not layered together.

Example `.treeignore`:

```text
# Additional exclusions
exclude: coverage, cache, generated/assets
maxdepth: 0
showmode: all
```

Supported directive aliases:

| Setting | Accepted keys |
| --- | --- |
| Exclusions | exclude, ignore, skip |
| Maximum depth | maxdepth, depth |
| Export display mode | showmode, show |

Colon or equals separates a key and value. Exclusions can be comma/semicolon
separated; bare lines also add exclusions. Blank lines and lines starting with
hash or semicolon are ignored. A basename exclusion matches path components;
a relative path exclusion applies beneath the root. This is not full gitignore
glob/negation syntax. Local scans also recognize only simple directory-name
rules from `.gitignore`; complex wildcard/path/negation rules are skipped.

The parser records a template setting, but it does not automatically select
scaffold's preset. Use the explicit scaffold template option.

Depth counts path components below the scanned root. Zero is unlimited.
Export/watch depth precedence is explicit option, configuration, then five.
Export display precedence is explicit option, configuration, then all.
Verify gets depth from configuration, then five; it has no public depth option.
Expected and actual comparison entries use the same depth and exclusions.
Out-of-scope expected entries are not treated as missing.

## Synchronization

Verification reports missing, extra, matched, and possible moved entries.
Move detection is a suggestion; it does not change authoritative differences
and does not automatically relocate existing files.

Without sync, verification makes no layout changes. With sync, it creates
missing directories and missing file stubs or declared content. It does not
overwrite matched files to reconcile file bytes.

Delete-extras must be explicitly combined with sync. Extra files can be deleted;
directories are removed only when empty. Excluded or depth-limited descendants
are preserved. Possible move sources and related paths are protected, which
can intentionally leave drift after sync.

An incomplete initial scan prevents synchronization. The plan is checked before
writes, and a fresh scan determines the final report and exit status.
Runtime failures may leave partial completed operations; sync reports counts
and returns failure rather than claiming a clean result. Sync is not a
transactional rollback system. Review changes on important directories before
requesting deletion.

The scaffold creation log is a real file; if your expected structure does not
include or exclude it, verification may report it as extra.

## Watch lifecycle

Watch subscribes before its initial snapshot, coalesces event bursts with a
250 ms debounce, and periodically rescans every five seconds.
Events outside configured exclusions/depth are filtered.
Overflow/error events trigger a full rescan. Incomplete snapshots produce
warnings and retries rather than a false clean comparison.
Stopping watch disposes its watcher and removes its own event subscriptions.
Watch reports structure; it never applies sync automatically.

## Credentials

Auth stores credentials with the native Windows credential vault API under
canonical targets such as `git:https://github.com` or a repository-specific
HTTPS target. These credentials persist in Windows Credential Manager under
the current Windows account. They are not stored in repository files.

Store takes a masked prompt or one environment/stdin secret channel. Do not put
tokens in command arguments. Clear removes the selected target and is idempotent.

Remote lookup tries repository-specific credentials, then host credentials;
available Git credential helpers are fallback lookup sources.
Helper requests use captured input/output with a bounded wait and no interactive
credential prompt. Public CI requests can proceed anonymously; private requests
fail if authorization is unavailable. Credential availability, API permissions,
and rate limits still determine whether a request succeeds.

## Remote request behavior

Repository layout requests require HTTPS, encode branch/path values, and use
bounded timeouts and transient-error retries. Redirects are not followed.
GitHub's truncated recursive-tree response is rejected. GitLab responses and
pagination are checked, with a maximum page bound.
A failed request or incomplete tree must not be interpreted as an empty repository.

The version command uses its own legacy GitLab tag-check implementation.
Its target differs from the current GitHub repository; see [version](CLI.md#version).

## Saved library and recovery

The library belongs to this utility installation:

| Path | Purpose |
| --- | --- |
| `data/store_data.json` | Versioned index and entry metadata |
| `data/store_trees/` | Managed copies of saved structures |
| `data/store_data.json.bak` | Previous index from atomic replacement |
| `data/store_data.json.lock` | Exclusive-access lock file |
| `data/store_data.json.transaction` | Pending-operation recovery journal |

Saved copies use managed text filenames; their actual input format is stored
in the index. Legacy paths prefixed with data are normalized within the library.
Invalid indexes and paths outside the library are rejected rather than silently
reset.

Writes serialize through an exclusive lock (up to five seconds waiting).
Index replacement is atomic and flushed, with a previous-index backup.
Save/rename/delete/purge stage file operations and journal their intended index
change. On subsequent access, interrupted operations are completed or rolled
back according to the committed index state. Ambiguous state is preserved for
manual investigation.

If recovery reports an error:

1. Stop other tool processes using this library.
2. Copy the entire data directory, including the index, backup, journal, and
   saved files, to a separate backup location.
3. Inspect the error and compare current/backup indexes with the actual files.
   A backup index alone may not match files changed by later operations.
4. Repair a consistent index/fileset before retrying. Do not remove the journal
   or reset the index merely to suppress the error.

The backup is the previous index, not a complete historical backup of every
saved file. Keep independent backups for structures you need to retain.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Ambiguous format | Supply the explicit input format |
| Invalid name/path | Check Windows names, hierarchy, and destination ancestry |
| Missing expected entries ignored | Check configured depth and exclusions |
| Export/sync refuses a scan | Resolve access errors or reparse points first |
| CI waits indefinitely | Check whether the command is watch; it is continuous |
| Library is busy | Let the active operation finish, then retry |
| Private API access fails | Check the credential target, token scope, and API status |
| Update check differs from GitHub | The checker still targets legacy GitLab tags |

A command error includes contextual information. Preserve that output and the
exit status when reporting a bug; omit secrets and sensitive path details.
