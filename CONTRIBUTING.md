# Contributing to Project Tree Utility

Thanks for your interest in contributing. This document covers everything you
need to get started.

---

## 🛠️ Our Branching Strategy

To keep our production environment completely stable, we use two primary branches:
* **`main`**: Contains the stable, production-ready code. **Do not branch off or target Merge Requests directly to `main`.**
* **`dev`**: The staging ground for all active development and upcoming features. 

**Rule:** Always create your feature or bugfix branches off of `dev`, and ensure your final Merge Request targets `dev`.

---

## Before you begin

- Check the [issue tracker](https://gitlab.com/tanvirfoysaltoshin/project-tree-utility/-/issues)
  to see if your bug or feature is already being discussed.
- For significant changes, open an issue first so we can align before you
  invest time writing code.
- Small fixes (typos, broken error messages, documentation) can go straight
  to a merge request.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built into Windows — no install needed)
- A text editor (VS Code recommended for `.ps1` and `.bat` syntax highlighting)
- Git (for cloning and branching)

No build step, no package manager, no compiler. Clone and run.

```bat
git clone https://gitlab.com/tanvirfoysaltoshin/project-tree-utility.git
cd project-tree-utility
tree.bat
```

---

## Branch naming

| Type | Pattern | Example |
|---|---|---|
| New feature | `feat/short-description` | `feat/json-export` |
| Bug fix | `fix/short-description` | `fix/verify-ignore-file` |
| Documentation | `docs/short-description` | `docs/update-readme` |
| Refactor | `refactor/short-description` | `refactor/shared-helpers` |

Branch off `main`. Do not commit directly to `main`.

---

## Where things live

```
bin/        ← .bat wrappers — argument parsing, CI mode, handoff to PS1
src/        ← PowerShell backend — all business logic lives here
src/internal/_shared.ps1  ← shared library dot-sourced by every PS1
data/       ← runtime-generated, not committed
```

**Rule:** business logic belongs in `.ps1`, not in `.bat`. The `.bat` files
are thin wrappers. If you are writing more than argument parsing and a single
`powershell ... -File` call in a `.bat`, the logic should move to a `.ps1`.

---

## Adding a new subcommand

1. Create `src/yourcommand.ps1` with a `param()` block. Always include
   `[switch]$Ci` as an optional parameter.
2. Create `bin/yourcommand.bat` following the pattern of any existing `.bat`.
   Detect `--ci` and `TREE_CI`, skip `pause` in CI mode, pass args through.
3. Register it in `tree.bat` in three places:
   - CLI passthrough block (the `if /i "%~1"=="..."` lines near the top)
   - Missing-file check block
   - Main menu display and choice handler (pick the next available number)

---

## Adding a template preset

In `src/internal/_shared.ps1`, find the `Get-TemplatePreset` function and add
a new `switch` case. Each entry in the preset is a hashtable with:

```powershell
@{ Path = 'relative/path'; IsDir = $false; Content = 'file content here' }
@{ Path = 'src/';          IsDir = $true  }
```

Then add the name to the Step 0 picker menu in `bin/scaffold.bat`.

---

## Adding a new structure file format

In `src/internal/_shared.ps1`, touch three functions:

- `Get-StructureFormat` — add auto-detection logic
- `Read-StructureFile` — add a parser branch that returns a flat list of
  entry objects with `Name`, `Depth`, `IsDir`, `Path` properties
- `Confirm-StructureFormat` — add a validation branch

---

## Code style

**PowerShell:**
- Use `[void]` or `| Out-Null` to suppress unwanted pipeline output
- Use `Write-Color` (from `_shared.ps1`) for all console status messages —
  not bare `Write-Host`
- Never use `Write-Color` on text that goes into a `StringBuilder` report —
  report files must be plain text
- Prefer `[System.Collections.Generic.List[object]]` over arrays for lists
  that grow in loops
- Always guard disk writes with `Test-SafePath` and `Test-DangerousName`

**Batch:**
- Use `setlocal enabledelayedexpansion` and `!variable!` syntax consistently
- Always clean up temp files (`.ps1`, `.vbs`) in both success and error paths
- Exit codes: `0` = success, `1` = failure, `2` = internal/setup error

**Both:**
- Keep error messages prefixed: `[ERROR]`, `[WARN]`, `[INFO]`, `[OK]`,
  `[SECURITY]`, `[SKIP]`
- Match the prefix convention of the file you are editing

---

## Security rules — non-negotiable

These apply to every contribution that touches disk writes or credential
handling:

- All structure file entries must pass `Test-SafePath` and `Test-DangerousName`
  before any folder or file is created
- No credential, token, or secret may be written to disk in any form
- Path traversal must be blocked — the `Test-SafePath` check in
  `src/internal/_shared.ps1` is the authority; call it, do not reimplement it
- `--ci` mode must never bypass security checks — it only suppresses prompts

A merge request that weakens any of the above will not be accepted regardless
of other merits.

---

## Testing your changes

There is no automated test suite yet. Before submitting a merge request, run
through the affected subcommand manually:

1. Happy path — normal interactive use
2. CI path — `tree.bat --ci <subcommand> <args>` with all required arguments
3. Error path — missing file, invalid format, bad path — confirm error messages
   and exit codes are correct
4. Edge case — empty structure file, very deep nesting, Unicode filenames if
   relevant

Document what you tested in your merge request description.

---

## Submitting a merge request

1. Fork the repository on GitLab
2. Clone your fork locally and switch to the development branch: `git checkout dev`.
3. Create a branch off of dev following the branch naming convention above (`git checkout -b feat/your-feature`).
4. Make your changes and commit them cleanly.
5. Update `CHANGELOG.md` under an `## [Unreleased]` heading
6. Update `README.md` if you added a subcommand, format, or flag
7. Push your branch to your fork and open a Merge Request with:
   - A clear title (`fix: verify ignores .treeignore` or `feat: add xml export`)
   - A description of what changed and why
   - What you tested manually

⚠️ **Important:** Ensure your Merge Request targets our `dev` branch, not `main`.

---

## Reporting bugs

Open an issue with:
- Windows version (`winver`)
- PowerShell version (`$PSVersionTable.PSVersion`)
- The exact command you ran
- The full console output including any error messages
- The structure file content if relevant (redact any sensitive paths)

---

## Questions

Open an issue tagged `question` or reach out directly:
**tanvirfoysaltoshin@gmail.com**
