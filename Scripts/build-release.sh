#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Linux ]]; then
    printf 'This release build targets glibc Linux. Build on a native glibc Linux host.\n' >&2
    exit 1
fi

# Embed the Swift runtime and Foundation while retaining the host's glibc backend.
swift build -c release --static-swift-stdlib
release_directory=$(swift build -c release --show-bin-path)
mkdir -p bin
cp "$release_directory/locale-editor" bin/locale-editor.new
chmod 755 bin/locale-editor.new
mv -f bin/locale-editor.new bin/locale-editor

dependencies=$(ldd bin/locale-editor)
printf '%s\n' "$dependencies"
if printf '%s\n' "$dependencies" | grep -Eq 'lib(swift|Foundation|dispatch|BlocksRuntime)'; then
    printf 'The release unexpectedly depends on shared Swift runtime libraries.\n' >&2
    exit 1
fi
./bin/locale-editor --help >/dev/null
printf 'Release executable: %s/bin/locale-editor\n' "$PWD"
