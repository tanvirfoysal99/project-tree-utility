# Installation and supported environments

After installation, use [Getting started](GETTING_STARTED.md) for exactly where
to type commands and [Complete CLI reference](CLI.md) for all 12 operations and flags.

## Distribution contract

| Platform | Delivery | User runtime requirements |
| --- | --- | --- |
| Windows x64 | Portable executable/archive, optional user-local installation | Supported Windows and packaged native runtime dependencies |
| Linux x64/ARM64 | Terminal installer or compiled executable | Compatible libc and system runtime libraries |
| macOS Apple Silicon/Intel | Terminal installer or executable | Supported macOS version; signing/notarization for public distribution |
| Android ARM64 | Termux-specific executable installed through its terminal | Termux and compatible Android API/runtime |

iOS/iPadOS is outside scope. Platform support is an implementation target until
native tests and packaged-artifact checks pass. Rust itself supports additional
architectures; this project does not claim them without validation.

## Build from this source

Use Rust stable (manifest minimum 1.88). Build prerequisites include a linker and
C toolchain because TLS dependencies contain native code.

```sh
cargo build --release --locked
./target/release/ptu --help
```

Windows: use Rust's MSVC toolchain with Visual Studio C++ Build Tools, or a
compatible GNU toolchain with MinGW-w64. In PowerShell:

```powershell
cargo build --release --locked
.\target\release\ptu.exe --help
```

Ubuntu: install build tools (for example `build-essential` and `pkg-config`),
then Rust. macOS: install Xcode Command Line Tools, then Rust. These developer
tools are needed for compilation, not for correctly packaged end-user releases.

Termux: use its packaged toolchain rather than assuming a desktop Linux binary
will work:

```sh
pkg update
pkg install rust clang make pkg-config git
# Enter a checkout of this standalone Rust project, or its release/ subdirectory.
cargo build --release --locked
sh scripts/install.sh --from ./target/release/ptu
ptu --help
```

Keep projects in Termux's private home for reliable permissions and executable
support. Shared Android storage may have permission/filesystem limitations.
The tool can only access files permitted to the Termux process. Secure credential
storage requires a configured compatible Git helper; it is not silently emulated
with plaintext files.

## Install a locally built executable

Linux/macOS:

```sh
sh scripts/install.sh --from ./target/release/ptu
```

The destination defaults to `$HOME/.local/bin`, or `$PREFIX/bin` in Termux.
Use `--prefix /your/bin/directory` to override it. Add the chosen directory to
your shell's `PATH` if needed. No root privileges are required for user-local use.

Windows can run the executable in place without installation. Optional user-local
copy and PATH registration:

```powershell
.\scripts\install.ps1 -Binary .\target\release\ptu.exe -AddToPath
```

Reopen the terminal after a persistent PATH change. CMD users can run
`ptu.exe` from the extracted directory or its full path without PowerShell.
The installer is a convenience, not a runtime dependency.

## Published terminal downloads

The shell installer supports a versioned release archive plus SHA-256 manifest:

```sh
sh scripts/install.sh --version 3.0.0
```

**This works only after the maintainer publishes `rust-v3.0.0` and the matching
assets. No such remote publication is performed by building this directory.**
The installer downloads a platform-specific archive, verifies its checksum,
and installs the executable without a graphical installer. Checksum verification
detects corruption; it is not an independent signature of the release publisher.

A Homebrew formula, WinGet package, Ubuntu repository, and official Termux package
are not registered by this project. Do not advertise `brew install ptu`,
`apt install ptu`, or `pkg install ptu` until the relevant distribution exists.

## Uninstall and updates

Remove the installed executable and any PATH entry you added. User library data
is retained unless explicitly removed. `ptu library purge --yes` removes managed
records, not arbitrary directories. Install a verified newer executable to update;
`version --check` only reports upstream metadata and never self-updates.
