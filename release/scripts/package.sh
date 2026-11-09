#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version=${1:-3.0.0}
case "$version" in *[!0-9.]*|'') echo 'Invalid version' >&2; exit 2 ;; esac
case "$(uname -s)" in Linux) platform=linux ;; Darwin) platform=macos ;; *) echo 'Unsupported packaging host' >&2; exit 2 ;; esac
if [ -n "${TERMUX_VERSION:-}" ]; then platform=android; fi
case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; *) echo 'Unsupported architecture' >&2; exit 2 ;; esac
cargo build --release --locked
stage="dist/ptu-$version-$platform-$arch"
mkdir -p "$stage/docs"
cp target/release/ptu README.md LICENSE.md CHANGELOG.md CONTRIBUTING.md Cargo.toml Cargo.lock .gitignore "$stage/"
cp docs/*.md "$stage/docs/"
cp -R src tests scripts examples .github "$stage/"
asset="ptu-$version-$platform-$arch.tar.gz"
tar -czf "dist/$asset" -C "$stage" ptu README.md LICENSE.md CHANGELOG.md CONTRIBUTING.md Cargo.toml Cargo.lock .gitignore docs src tests scripts examples .github
if command -v sha256sum >/dev/null 2>&1; then (cd dist && sha256sum "$asset") > dist/SHA256SUMS; else (cd dist && shasum -a 256 "$asset") > dist/SHA256SUMS; fi
echo "dist/$asset"
