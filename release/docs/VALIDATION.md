# Validation record

Observed on **9 November 2026**, using Rust/Cargo 1.99.1 and the
`x86_64-pc-windows-gnu` toolchain with MinGW-w64. All project files, caches,
generated build outputs, and installer smoke destinations used for this work are
inside this Rust directory. Intended platform support must not be read as
evidence of native execution on another OS.

## Completed checks

| Check | Observed result |
| --- | --- |
| `cargo fmt --all -- --check` | Passed |
| `cargo clippy --all-targets --locked -- -D warnings` | Passed without warnings |
| `cargo test --locked` | 83 passed, 0 failed; native-vault test skipped by default |
| Explicit native-vault integration | 1 passed; unique dummy record stored, updated, and cleared |
| `cargo build --release --locked` | Passed; optimized Windows x64 `ptu.exe` |
| Interactive Windows console | Reproduced and fixed CRLF parsing; `--help`, `version`, and `export --help` passed with actual terminal Enter input |
| Optimized runtime without Rust/MinGW on PATH | `ptu --version` passed |
| Optimized end-to-end workflow | YAML import → JSON → scaffold → clean verify → YAML export → sync/delete-extra → clean verify passed |
| Windows junction guard | Refusal of scan, destination write, and sync passed |
| Library concurrency | Six concurrent writers serialized with no lost records |
| HTTP fixtures | Loopback retry, redirect, authorization, malformed/oversized response checks passed |
| Watch process | Reported drift and did not synchronize |
| Interactive watch lifecycle | Ctrl+C stopped watch and a second watch started in the same menu |
| Live providers | Anonymous GitHub and GitLab exports passed; later GitHub requests exhausted the shared anonymous quota (HTTP 403, remaining 0) |
| Version lookup | No published upstream release reported successfully; published/invalid release fixtures also tested |
| Generated application builds | React/Vite and Hono Worker install/typecheck/build passed; pnpm workspace install/recursive build/test passed |
| Extracted portable ZIP | 24 CLI/command/watch/vault checks passed; checksum, binary identity, required files, local Markdown links, and Windows-only PATH startup passed |
| Tree-symbol output | Exact nested connectors, empty directories, Unicode/content/template round-trips, all/files/folders modes, auto-detection, and actual Windows menu/typed-command output checked |
| Installer smoke checks | User-local Windows copy and POSIX installer under Git sh passed inside `target/` |
| Shell/PowerShell script syntax | Both installer and packaging scripts passed |
| Documentation links and whitespace | Local links resolved; formatting and whitespace checks passed |
| Complete documentation reference | All 12 commands, 70 option bindings, 7 input names, 8 output names, and 27 renamed aliases checked against source; all help commands and first-run workflow passed |
| Existing parent project | Legacy files outside `release/` remain unchanged |

PE import inspection of the optimized binary found Windows system/API-set DLLs
and no MinGW runtime DLL imports. This is evidence for this particular build,
not a guarantee about artifacts produced by another toolchain. Running it with
an isolated Windows-only PATH succeeded. Native Windows runtime facilities such
as UCRT remain operating-system requirements.

The POSIX installer smoke check on Windows validates its shell workflow only;
it is not a Linux/macOS/Android execution claim. The license copy matches the
parent project's license byte-for-byte. The nested CI workflow has not been
executed remotely or activated in the parent repository.

## Additional platform gates

Linux, macOS, and Termux need native test and packaged-artifact runs before a
production compatibility claim. Windows native-vault integration was explicitly
tested with a dummy credential. Native vault/helper integration on other systems
is still pending. See [the QA report](QA_REPORT.md) for command coverage, corrected
defects, and the distinction between deterministic and live API checks.

No release assets, package-manager registrations, or remote deployments are
published as part of creating this project.

## Repository cleanup

The source checkout retains the Rust sources, Cargo manifests/lockfile, complete
documentation, tests, examples, installation/packaging scripts, and standalone
CI template. Generated `target/` builds, disposable test projects, npm caches,
the project-local `.tools/` toolchain, and duplicate extracted/package staging
directories are disposable and are removed after validation. Use an installed
Rust toolchain for subsequent builds; Cargo recreates `target/` as needed.

The final portable ZIP and `SHA256SUMS` may remain locally in ignored `dist/`.
They are generated distribution artifacts, not Git source files. Recreate them
with the packaging script; publishing downloadable assets is a separate step.
