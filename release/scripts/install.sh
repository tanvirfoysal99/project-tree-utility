#!/bin/sh
# User-local installation. Published downloads require matching rust-v* assets.
set -eu

source_binary=
version=
destination=${HOME:?HOME is required}/.local/bin
if [ -n "${TERMUX_VERSION:-}" ]; then destination=${PREFIX:?PREFIX is required}/bin; fi
while [ "$#" -gt 0 ]; do
    case "$1" in
        --from) source_binary=${2:?--from requires a binary path}; shift 2 ;;
        --version) version=${2:?--version requires a release version}; shift 2 ;;
        --prefix) destination=${2:?--prefix requires a bin directory}; shift 2 ;;
        -h|--help) echo 'Usage: sh install.sh (--from PATH | --version X.Y.Z) [--prefix BIN_DIRECTORY]'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
if [ -n "$source_binary" ] && [ -n "$version" ]; then echo 'Choose --from or --version' >&2; exit 2; fi
scratch=
staged=
cleanup() {
    if [ -n "$staged" ]; then rm -f -- "$staged"; fi
    if [ -n "$scratch" ]; then rm -f -- "$scratch/archive.tar.gz" "$scratch/SHA256SUMS" "$scratch/ptu"; rmdir -- "$scratch" 2>/dev/null || :; fi
}
trap cleanup EXIT HUP INT TERM
if [ -n "$version" ]; then
    case "$version" in *[!0-9.]*|'') echo 'Version must contain only digits and dots' >&2; exit 2 ;; esac
    case "$(uname -s)" in Linux) platform=linux ;; Darwin) platform=macos ;; *) echo 'Unsupported installer platform' >&2; exit 2 ;; esac
    if [ -n "${TERMUX_VERSION:-}" ]; then platform=android; fi
    case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; *) echo 'Unsupported CPU architecture' >&2; exit 2 ;; esac
    asset="ptu-$version-$platform-$arch.tar.gz"
    base="https://github.com/tanvirfoysal99/project-tree-utility/releases/download/rust-v$version"
    scratch=$(mktemp -d)
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' "$base/$asset" -o "$scratch/archive.tar.gz"
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' "$base/SHA256SUMS" -o "$scratch/SHA256SUMS"
    expected=$(awk -v asset="$asset" '$2 == asset { print $1 }' "$scratch/SHA256SUMS")
    [ "${#expected}" -eq 64 ] || { echo 'Checksum manifest has no unique matching asset' >&2; exit 1; }
    if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$scratch/archive.tar.gz" | awk '{print $1}'); else actual=$(shasum -a 256 "$scratch/archive.tar.gz" | awk '{print $1}'); fi
    [ "$actual" = "$expected" ] || { echo 'Checksum verification failed' >&2; exit 1; }
    tar -xzf "$scratch/archive.tar.gz" -C "$scratch" ptu
    source_binary=$scratch/ptu
fi
[ -n "$source_binary" ] || { echo 'Specify --from PATH or --version X.Y.Z' >&2; exit 2; }
[ -f "$source_binary" ] && [ ! -L "$source_binary" ] || { echo 'Source must be a regular executable file' >&2; exit 2; }
mkdir -p -- "$destination"
[ ! -d "$destination/ptu" ] || { echo 'Destination ptu is a directory' >&2; exit 2; }
staged=$(mktemp "$destination/.ptu.XXXXXX")
cp -- "$source_binary" "$staged"
chmod 755 "$staged"
mv -f -- "$staged" "$destination/ptu"
staged=
echo "Installed $destination/ptu"
case ":${PATH:-}:" in *":$destination:"*) ;; *) echo "Add $destination to PATH to run ptu from any directory." ;; esac
