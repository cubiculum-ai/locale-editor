#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Linux ]] || { echo 'Build Debian packages on Linux.' >&2; exit 1; }
version=${LOCALE_EDITOR_PACKAGE_VERSION:-0.2.0-2}
architecture=$(dpkg --print-architecture)
build_jobs=${LOCALE_EDITOR_BUILD_JOBS:-4}
[[ $build_jobs =~ ^[1-9][0-9]*$ ]] || { echo 'Build jobs must be a positive integer.' >&2; exit 1; }
case "$version" in *[!0-9A-Za-z.+:~\-]*|'') echo 'Invalid package version' >&2; exit 1;; esac
mkdir -p dist
for variant in tui gui; do
    if [[ $variant == gui ]]; then export LOCALE_EDITOR_GUI=1; else export LOCALE_EDITOR_GUI=0; fi
    scratch="$PWD/.build/package-$variant"
    swift build --jobs "$build_jobs" --scratch-path "$scratch" -c release --static-swift-stdlib
    binary="$(swift build --scratch-path "$scratch" -c release --show-bin-path)/locale-editor"
    dependencies=$(ldd "$binary")
    if printf '%s\n' "$dependencies" | grep -Eq 'lib(swift|Foundation|dispatch|BlocksRuntime)'; then
        echo 'Release requires shared Swift libraries; refusing to package.' >&2; exit 1
    fi
    if [[ $variant == tui ]] && printf '%s\n' "$dependencies" | grep -Eqi 'lib(gtk|gdk|Qt|X11|wayland|polkit)'; then
        echo 'Terminal-only binary unexpectedly links graphical libraries.' >&2; exit 1
    fi
    mkdir -p "bin/$variant"
    install -m 755 "$binary" "bin/$variant/locale-editor"
    ln -sfn locale-editor "bin/$variant/locale-editor-tui"
    ln -sfn locale-editor "bin/$variant/locale-edit"
    ln -sfn locale-editor "bin/$variant/locale-edit-tui"
    stage="$PWD/.build/debian-$variant"
    # Only this script's disposable staging directory is replaced.
    rm -rf "$stage"
    mkdir -p "$stage/root/DEBIAN" "$stage/root/usr/bin" "$stage/root/usr/share/polkit-1/actions" "$stage/root/usr/share/doc/locale-editor-$variant" "$stage/debian" "$stage/root/usr/share/icons/hicolor/scalable/apps"
    chmod 755 "$stage/root/DEBIAN"
    install -m 755 "$binary" "$stage/root/usr/bin/locale-editor"
    for alias in locale-edit locale-editor-tui locale-edit-tui; do ln -s locale-editor "$stage/root/usr/bin/$alias"; done
    install -m 644 Packaging/org.linuxlocaleeditor.install.policy "$stage/root/usr/share/polkit-1/actions/"
    install -m 644 Packaging/org.linuxlocaleeditor.Editor.svg "$stage/root/usr/share/icons/hicolor/scalable/apps/"
    install -m 644 README.md "$stage/root/usr/share/doc/locale-editor-$variant/README.md"
    install -m 644 LICENSE "$stage/root/usr/share/doc/locale-editor-$variant/copyright"
    cp -R ThirdParty "$stage/root/usr/share/doc/locale-editor-$variant/ThirdParty"
    cat > "$stage/debian/control" <<CONTROL
Source: locale-editor
Section: utils
Priority: optional
Maintainer: rcfa <1831995+rcfa@users.noreply.github.com>

Package: locale-editor-$variant
Architecture: any
Description: Linux locale editor
CONTROL
    shared=$(cd "$stage" && dpkg-shlibdeps -O -e"$stage/root/usr/bin/locale-editor" | sed -n 's/^shlibs:Depends=//p')
    if [[ -z $shared ]]; then echo 'Cannot determine runtime dependencies.' >&2; exit 1; fi
    other=gui; description='Terminal editor for composing and installing glibc locales'
    if [[ $variant == gui ]]; then
        other=tui; description='Native GTK locale editor with a terminal interface'
        mkdir -p "$stage/root/usr/share/applications"
        install -m 644 Packaging/org.linuxlocaleeditor.Editor.desktop "$stage/root/usr/share/applications/"
        desktop-file-validate "$stage/root/usr/share/applications/org.linuxlocaleeditor.Editor.desktop"
    fi
    size=$(du -sk "$stage/root/usr" | cut -f1)
    cat > "$stage/root/DEBIAN/control" <<CONTROL
Package: locale-editor-$variant
Version: $version
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: rcfa <1831995+rcfa@users.noreply.github.com>
Installed-Size: $size
Depends: $shared, locales, pkexec
Provides: locale-editor (= $version)
Conflicts: locale-editor-$other
Replaces: locale-editor-$other
Description: $description
 Compose locales with per-section inheritance, international presets,
 formatted glibc previews, and personal or system-wide installation.
 The GUI and terminal-only packages are mutually exclusive.
CONTROL
    # Shared developer directories can carry setgid; never propagate that to /usr.
    python3 - "$stage/root" <<'PY'
import os, sys
for directory, _, _ in os.walk(sys.argv[1]):
    os.chmod(directory, 0o755)
PY
    dpkg-deb --root-owner-group --build "$stage/root" "dist/locale-editor-${variant}_${version}_${architecture}.deb"
done
sha256sum dist/locale-editor-*"_${version}_${architecture}.deb" > "dist/SHA256SUMS-${version}-${architecture}"
echo "Packages are in $PWD/dist"
