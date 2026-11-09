# Pre-release QA report

**Scope:** the Rust edition in this directory, on Windows x64, 9 November 2026.
The legacy PowerShell/Batch project outside this directory was left unchanged.
This is a functional source review and command-validation record, not a claim
of a formal security audit or native validation on other operating systems.

## Results

- 83 default Rust tests pass. One native-vault test is intentionally ignored in
  the default run and was explicitly executed successfully: **84 tests executed,
  zero failures**.
- Rustfmt and Clippy with warnings treated as errors pass. The optimized Windows
  executable builds successfully.
- All twelve public command names have help and invalid-input coverage. Success
  paths are exercised through subprocesses, provider fixtures, or live integration
  as specified below. Every numbered menu option has a complete-input test.
- Real Windows terminal checks cover help, import, export, scaffold, verify,
  merge, version, security actions, library actions, masked credential input,
  and watch stop/restart with Ctrl+C.
- React/Vite and Hono Worker install, typecheck, and build. Hono uses Wrangler
  dry-run and does not deploy. The pnpm preset installs and recursively builds
  and tests a disposable workspace child.
- Live anonymous GitHub and GitLab exports passed. Version lookup passed after
  correcting the no-published-release case. Later GitHub requests returned 403;
  response headers confirmed the shared anonymous quota was exhausted.
- Packaged-executable command matrix: **24 checks passed** against the extracted
  optimized executable (11 CLI, 10 command-matrix, 2 watch, 1 native-vault).
  ZIP checksum, executable identity, required files, all packaged Markdown links,
  and startup with Rust/MinGW removed from PATH also passed.

## Command coverage

The documentation was expanded into a complete [CLI reference](CLI.md),
[first-run guide](GETTING_STARTED.md), and [developer/API guide](DEVELOPER_GUIDE.md).
The documentation checker validates every parser command/option binding, input/
output format names, renamed aliases, local links/heading anchors, all twelve help
commands, and the documented first-run workflow.

| Command | Successful cases | Negative or boundary cases |
| --- | --- | --- |
| `import` | All six input formats; reusable/display/summary outputs; Unicode and exact content | Malformed schema/indentation/directives, duplicate keys/paths, traversal, size/depth limits |
| `export` | Tree symbols/JSON/YAML/dash/text/Markdown/summary; all/files/folders; CLI/config precedence | Incomplete/junction scans, missing output parent, invalid format/options |
| `scaffold` | Layouts, three presets, dry-run, skip/overwrite, guided menu | Reserved log, type conflict, read-only overwrite, traversal, invalid/missing input |
| `verify` | Clean/drift exit codes, create missing, delete eligible extras, final rescan | Type conflicts, excluded descendants, possible moves including Windows casing, deletion without sync |
| `merge` | Preference strategies, union metadata, guided menu | Conflicting types/content, missing options, output preservation on failure |
| `watch` | Real subprocess drift, read-only behavior; interactive stop and restart | Invalid interval, incomplete snapshot handling, no implicit synchronization |
| `gittree` | Live anonymous GitHub/GitLab; deterministic branch encoding, subfolders, pagination | Truncated/malformed responses, invalid pages/URLs, transport errors, redirects, oversized bodies, rate limiting |
| `auth` | Native dummy record store/lookup/update/clear, stdin/environment/masked input | Empty/invalid token, invalid target, literal/duplicate channels, CI prompt refusal |
| `library` | Save/list/open/rename/delete/purge, duplicate suffixes, concurrent writers | Corrupt snapshot preservation, failed-commit rollback, name conflicts, missing entries, purge confirmation |
| `security` | VALIDATE_FILE, VALIDATE_NAMES, VALIDATE_ALL, VALIDATE_PATH; guided inputs | Outside-base paths, unsafe structure paths, malformed schemas |
| `detection` | ANALYSE and BUILD_TREE through executable | Malformed positional forms and conflicting merges |
| `version` | Local version, absent upstream release, published-release fixture | API denial/rate limit, malformed release tags, transport failure |

The numbered Git Tree menu's argument construction is covered by the menu tests;
live exports use explicit `--anonymous` CLI mode so existing credentials are never
consulted. The masked credential prompt uses a unique `.invalid` host and dummy
secret; the record is cleared afterward. No real user tokens are used.

## Defects corrected

| Defect | Correction |
| --- | --- |
| Windows Enter retained an invisible carriage return | Remove console line endings before tokenization |
| Tree symbols were accepted as input but unavailable as output | Add `treesym` export/conversion, connectors, metadata round-trips, ancestor context, help, docs, and guided-menu choices |
| Content containing `type:` was misdetected as YAML | Match structural YAML keys rather than substrings inside content |
| Similar sibling names interrupted displayed parent/child groups | Sort display entries by hierarchical path components |
| A backtick filename could close the Markdown fence | Choose a fence longer than the longest filename backtick run |
| Read-only overwrite failed after earlier files were created | Refuse known read-only overwrite/log destinations during preflight |
| Failed library commit mutated in-memory state | Commit a candidate snapshot before adopting it in memory |
| Unicode name lookup used different case rules from snapshot validation | Use the same Unicode lowercase comparison for save, lookup, rename, and load |
| Windows case differences bypassed possible-move preservation | Use Windows case rules for basename matching |
| `--ci` after `--` was consumed as a switch | Preserve literal arguments after the end-of-options marker |
| Invalid library commands created storage directories | Validate required inputs/actions before dispatching side effects |
| Security menu actions omitted base/candidate inputs | Prompt for the fields required by each selected action |
| Uppercase auth/menu actions were inconsistently handled | Normalize action names consistently |
| Unpublished upstream release produced a generic 404 failure | Report that no release comparison is available |
| Repository `.git` suffix/base handling could change identity | Strip a single suffix and validate namespace below the base |
| Unix atomic replacement discarded executable permissions | Preserve existing Unix permissions; native Unix execution remains a platform gate |
| Portable README referenced omitted source/test/script files | Include the referenced project files in the artifact |

Regression coverage is in [review regressions](../tests/review_regressions.rs),
[command matrix](../tests/commands.rs), [provider fixtures](../tests/remote_providers.rs),
and the existing format/filesystem/CLI suites.

## Reproduction

```powershell
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
cargo test --locked --test native_auth -- --ignored
.\tests\live-commands.ps1
.\tests\template-builds.ps1
cargo build --release --locked
.\scripts\package.ps1
.\tests\package-check.ps1 -IncludeNativeAuth
```

Live checks require network access and available provider quotas. The native-vault
test and template scripts are opt-in because they touch a dummy vault record or
download dependencies. Template builds retain disposable fixtures under `target/`
for inspection and use a project-local npm cache. Nothing is deployed or published.

## Remaining platform gates

Native Linux, macOS, and Android/Termux runs are still required before publishing
those artifacts. No Linux development distribution or running Docker engine was
available in this workspace; macOS and Android execution were unavailable.
Cross-platform source support and a CI template are not substitutes for those
checks. GitHub 403 at an exhausted quota is an external API condition, not evidence
of a successful current remote request. The CLI correctly returns an error in that
case instead of producing a partial layout.
