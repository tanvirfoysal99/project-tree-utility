# Contributing to Project Tree Utility

The project is hosted on [GitHub](https://github.com/tanvirfoysal99/project-tree-utility).
Use the [issue tracker](https://github.com/tanvirfoysal99/project-tree-utility/issues)
for reproducible bugs and proposed changes.

## Requirements

Use Windows 10/11, Windows PowerShell 5.1, Git, and a text editor.
Regression tests require no npm packages. Optional template builds require
Node.js 22.12+ and network access to npm.

## Branch workflow

This repository uses exactly two branches:

| Branch | Role |
| --- | --- |
| `master` | Default branch containing verified changes |
| `develop` | Active development branch used on this PC |

Keep this PC checked out on `develop`, tracking `origin/develop`. Push authorized
development changes to `origin/develop`. After verification, integrate them into
`origin/master` and synchronize both branches to the same commit.
Do not create additional feature, fix, or automation branches for this workflow.

Inspect `git status` and fetch before starting. Preserve unrelated working
changes and existing commits. Prefer fast-forward updates; if branches diverge,
resolve and test the integration on `develop` before updating `master`.
Avoid force pushes.

For an already synchronized checkout:

```powershell
git switch develop
git branch --set-upstream-to=origin/develop develop
git fetch origin --prune
git merge --ff-only origin/develop
```

Commit, push, and merge only when requested by the repository owner. After an
authorized integration, verify local `develop`, local `master`,
`origin/develop`, and `origin/master` point to the intended commit.
Leave `develop` checked out.

## Source layout

| Location | Responsibility |
| --- | --- |
| `tree.bat` | Public entry point and interactive menu |
| `bin/*.bat` | Wrappers and legacy interactive flows |
| `src/cli.ps1` | Shared public argument parsing, validation, and routing |
| `src/*.ps1` | Command implementations and action adapters |
| `src/internal/_shared.ps1` | Structure, path, configuration, and content helpers |
| `src/internal/_scan.ps1`, `_merge.ps1`, `_yaml.ps1` | Scanning, merging, and YAML parsing |
| `src/internal/_library_transactions.ps1` | Serialized writes and recovery |
| `src/internal/_credentials.ps1`, `_http.ps1` | Credential and HTTP helpers |
| `src/internal/_templates.ps1`, `_watch.ps1` | Template and watcher helpers |
| `data/` | Ignored runtime library data |
| `tests/`, `docs/` | Automated checks and public guides |

## Implementation conventions

Keep business logic in PowerShell and pass input as data. Do not generate scripts
from interpolated paths or credentials. Maintain Windows PowerShell 5.1
compatibility; PowerShell 7 syntax alone is insufficient.

Use literal-path filesystem operations. Validate names, containment, and existing
ancestors before writes. Preserve scan errors and prevent mutation based on
incomplete comparisons. Catch failures at command boundaries, include useful
context, and preserve meaningful exit statuses.

Keep secrets out of arguments and logs. Use the existing environment/stdin secret
channels. Library mutations must use the transaction helpers.

For command changes:

1. Update the backend and option/positional routing in `src/cli.ps1`.
2. Update wrappers and menu entries where applicable.
3. Preserve CI behavior, argument forwarding, and exit status.
4. Add focused coverage to the suite that owns the behavior.
5. Update affected command, format, and operation documentation.

## Validation

Run from the repository root:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/run-regressions.ps1
git diff --check
```

See [the testing guide](tests/README.md) for suite selection, side effects, and
optional template builds. Report the exact checks performed. Do not claim builds
ran when only regression tests ran.

GitHub Actions runs regression and template-build jobs on Windows. The optional
GitLab configuration runs regressions on a Windows runner tagged `windows`.

## Documentation and reports

Document implemented defaults, limitations, exit codes, and filesystem effects.
Use runnable PowerShell examples and current GitHub links. Record new changes
under `[Unreleased]` without inventing release dates. Historical changelog
entries describe their release, not necessarily current behavior.

Describe the concrete problem, resulting behavior, relevant tradeoffs, and
validation. Keep legal license text intact unless a license change is explicitly
requested.
