#!/usr/bin/env bash
# Optional native arm64 build-host setup. Installs only into this checkout's .build directory.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -m) == aarch64 ]] || { echo 'Run this on an arm64 Linux build host.' >&2; exit 1; }
version=6.4.1
swift_root="$PWD/.build/swift-${version}-arm64"
archive="$PWD/.build/swift-${version}-arm64.tar.gz"
base="https://download.swift.org/swift-${version}-release/debian13-aarch64/swift-${version}-RELEASE/swift-${version}-RELEASE-debian13-aarch64.tar.gz"
mkdir -p .build
if [[ ! -x "$swift_root/usr/bin/swift" ]]; then
    curl --fail --location --retry 2 "$base" -o "$archive"
    curl --fail --location --retry 2 "$base.sig" -o "$archive.sig"
    keyring="$PWD/.build/swift-signing-keys"
    mkdir -p "$keyring"; chmod 700 "$keyring"
    curl --fail --location https://www.swift.org/keys/all-keys.asc -o "$keyring/swift.asc"
    gpg --batch --homedir "$keyring" --import "$keyring/swift.asc"
    gpg --batch --homedir "$keyring" --verify "$archive.sig" "$archive"
    mkdir -p "$swift_root"
    tar --no-same-owner -xzf "$archive" --strip-components=1 -C "$swift_root"
    rm "$archive" "$archive.sig"
fi
printf 'export PATH=%q:$PATH\n' "$swift_root/usr/bin" > .build/swift-arm64-env.sh
"$swift_root/usr/bin/swift" --version
echo 'Source .build/swift-arm64-env.sh before building.'
