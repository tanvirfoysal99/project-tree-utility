# Testing Project Tree Utility

Run checks on Windows with Windows PowerShell 5.1 (`powershell.exe`).
No test framework or npm dependency installation is required for regression suites.
Each suite is a standalone script using fixtures, assertions, and child processes.

## Run all regression suites

From the repository root:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/run-regressions.ps1
```

The runner discovers `*.tests.ps1` in this directory, sorts by filename, and
runs each in a separate Windows PowerShell process. It stops on the first failing
suite and also fails if no suites are found. Successful assertions print PASS;
failures include context and return a nonzero exit status.

## Suite coverage

| Suite | What it tests |
| --- | --- |
| `path-safety-library-and-sync.tests.ps1` | Source syntax/conflict markers; path containment, junctions and project names; saved-library lifecycle/index migration; sync preservation of excluded/depth-limited descendants; scaffold/export wrapper smoke checks |
| `scaffolding-and-format-roundtrips.tests.ps1` | Scaffold presets, preflight, dry-run and partial failures; dash/JSON/YAML round-trips; empty directories and content; adapter quoting/injection resistance |
| `structure-validation-and-cli.tests.ps1` | Format detection, hierarchy/node/name rejection; required CI input and no prompts; named/positional CLI contracts; exit propagation, special-character paths, library actions and argument forwarding |
| `scan-merge-transactions-and-credentials.tests.ps1` | Shared scan scope/errors and comparison; incomplete-scan mutation refusal; sync rescans/move protection; merge metadata/types; atomic library transactions, rollback, recovery and concurrency; credential vault and secret channels |
| `runtime-export-http-and-watch.tests.ps1` | Runtime/setup failures; depth/show-mode precedence and nested exports; template metadata; mock HTTP retries, URL encoding, truncated responses and pagination; actual watcher debounce, filtering, overflow and cleanup |

Run one suite directly when investigating a specific area:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/structure-validation-and-cli.tests.ps1
```

The suite names describe coverage instead of historical issue numbers. These are
regression scripts, not Pester files, despite their discoverable tests suffix.

## Fixtures and side effects

Suites use GUID-named temporary directories and disposable repository/backend
fixtures. Tests exercise actual file operations, child processes, junctions,
library locking/concurrency, and filesystem event subscriptions.
The credential suite writes, reads, and removes a uniquely named dummy vault
credential under an invalid fixture host; it does not need your real token.
Remote API paths are mocked, so regression tests do not require GitHub/GitLab
credentials or a live repository response.

Cleanup runs in finally blocks, with guarded temporary-directory removal.
Forced termination can leave a fixture behind; inspect its path before removing
it. Watcher checks involve real event timing. Assertion totals can change as
source files and coverage change; use the actual run output when reporting results.

## Optional application-template integration

Requires Node.js 22.12+ and npm network access:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/template-builds.ps1
```

This scaffolds disposable react-vite and hono-worker projects, runs npm install,
typecheck, and build from each generated project directory, then removes the
fixtures. Hono's build uses Wrangler dry-run and does not deploy.
The script sets CI/metrics environment values temporarily and restores them.
It does not build the monorepo-pnpm workspace preset.
These checks are separate from the regression runner because they download
dependencies and take longer.

## Continuous integration

[GitHub Actions](../.github/workflows/regression.yml) runs the shared regression
runner on Windows and the optional template builds with Node.js 22.
Both jobs must pass when reporting full CI success.

The [GitLab configuration](../.gitlab-ci.yml) provides the regression job for
a separately configured Windows shell runner tagged windows. It does not run
the optional npm integration checks.

Before reporting changes, also run `git diff --check` and verify that affected
documentation examples and file references use current paths.
