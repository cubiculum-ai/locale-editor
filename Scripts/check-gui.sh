#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -ge 1 ]] || { echo 'Usage: Scripts/check-gui.sh BINARY [CAPTURE_DIRECTORY]' >&2; exit 1; }
task_session=$(mktemp -d -t locale-editor-gui-session-XXXXXX)
cleanup() {
    # The private document portal may take a moment to release its FUSE mount.
    if mountpoint -q "$task_session/cache/doc"; then
        if command -v fusermount3 >/dev/null; then fusermount3 -u "$task_session/cache/doc" 2>/dev/null || true
        elif command -v fusermount >/dev/null; then fusermount -u "$task_session/cache/doc" 2>/dev/null || true; fi
    fi
    for attempt in 1 2 3 4 5; do
        mountpoint -q "$task_session/cache/doc" || break
        sleep 0.2
    done
    if ! mountpoint -q "$task_session/cache/doc"; then rm -rf "$task_session"; fi
}
trap cleanup EXIT
export XDG_CONFIG_HOME="$task_session/config" XDG_DATA_HOME="$task_session/data" XDG_CACHE_HOME="$task_session/cache"
export GSETTINGS_BACKEND=memory NO_AT_BRIDGE=0 GIO_USE_VFS=local GIO_USE_VOLUME_MONITOR=unix
export LOCALE_EDITOR_GUI_TEST_SESSION=1
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- python3 Scripts/test-gui.py "$@"
