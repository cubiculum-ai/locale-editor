#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_jobs=${LOCALE_EDITOR_BUILD_JOBS:-4}
swift build --jobs "$build_jobs"
export LOCALE_EDITOR_BINARY="$(swift build --show-bin-path)/locale-editor"
swift test --jobs "$build_jobs"
python3 Scripts/test-tui.py "$LOCALE_EDITOR_BINARY"
python3 Scripts/test-mouse.py "$LOCALE_EDITOR_BINARY"
python3 Scripts/test-menus.py "$LOCALE_EDITOR_BINARY"
python3 Scripts/test-files-and-formats.py "$LOCALE_EDITOR_BINARY"
python3 Scripts/test-postal-install.py "$LOCALE_EDITOR_BINARY"
python3 Scripts/test-international.py "$LOCALE_EDITOR_BINARY"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
"$LOCALE_EDITOR_BINARY" new --base en_GB --name en_GB.UTF-8@smoke --output "$task_tmp/project.json"
"$LOCALE_EDITOR_BINARY" export --project "$task_tmp/project.json" --output "$task_tmp/locale.src"
"$LOCALE_EDITOR_BINARY" preview --project "$task_tmp/project.json" > "$task_tmp/preview.json"
"$LOCALE_EDITOR_BINARY" compile --project "$task_tmp/project.json" --output "$task_tmp/compiled"
LOCPATH="$task_tmp/compiled" LC_ALL=en_GB.UTF-8@smoke date -u -d '2026-10-27 17:04:05' '+%x %X'
