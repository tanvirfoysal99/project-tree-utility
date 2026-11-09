# Release procedure

## Quality gate

Run formatting, warning-free Clippy, all tests, and an optimized build using
`Cargo.lock`. Review dependency changes, license notices, security limits,
installation docs, and migration notes. Exercise a disposable scaffold/export/
verify workflow using the actual packaged executable.

## Native platforms

Build and test separately on Windows, Linux, and macOS. Test Android binaries
inside Termux, including filesystem permissions, signal handling, DNS/TLS, and
credential-helper availability. Desktop Linux ARM64 output is not an Android
artifact. Maintain separate Apple Silicon/Intel builds when distributing both.

The nested `.github/workflows/ci.yml` is ready for use when this directory is a
standalone repository. GitHub ignores workflows nested under `release/` in the
parent repository. No parent CI files are modified. Android/Termux validation is
a separate manual gate and is not implied by the desktop CI template.

## Packaging

Windows x64, from a native x64 build environment:

```powershell
.\scripts\package.ps1
```

Linux/macOS/Termux, on the matching native architecture:

```sh
sh scripts/package.sh
```

Both build with `--release --locked`, place artifacts under `dist/`, include
documentation/license files, sources, tests, examples, and scripts, and produce
a SHA-256 manifest. The Windows script
labels x64 only; do not use it to label another architecture. Shell packaging
detects its host platform/architecture. These scripts do not upload or publish.

For each final executable, inspect native dependencies rather than assuming
that a single file means a fully static binary. For Windows GNU builds, ensure
any required MinGW DLLs are included or link the needed runtime statically.
For Linux, choose a compatible libc baseline; macOS releases should be signed
and notarized appropriately before public distribution. Native runtime/library
requirements must be documented with the exact artifacts.

## Publication

Use distinct Rust tags such as `rust-v3.0.0` to avoid confusing legacy releases.
The shell installer expects these asset names:

```text
ptu-3.0.0-linux-x86_64.tar.gz
ptu-3.0.0-linux-aarch64.tar.gz
ptu-3.0.0-macos-x86_64.tar.gz
ptu-3.0.0-macos-aarch64.tar.gz
ptu-3.0.0-android-aarch64.tar.gz
ptu-3.0.0-windows-x86_64.zip
SHA256SUMS
```

Publish only validated assets. Combine each platform's manifest into one
`SHA256SUMS` with one entry per published archive. The installer does not need
all listed architectures to exist; unsupported combinations fail to download.
Verify checksums after upload and test terminal installation in a disposable
user environment. Never claim package-manager registration until completed.
