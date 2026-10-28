#!/usr/bin/env python3
"""Exercise the real TUI through a PTY; verifies persistence and terminal restoration."""
import fcntl
import json
import os
import pathlib
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

binary = str(pathlib.Path(sys.argv[1]).resolve())
repo = pathlib.Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix="locale-tui-test-") as directory:
    saved = pathlib.Path(directory) / "edited.json"
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
    original = termios.tcgetattr(slave)
    base = "en_US" if sys.platform.startswith("linux") else "demo_en"
    process = subprocess.Popen(
        [binary, "--tui", "--sources", str(repo / "Examples/locales"), "--base", base, "--cursor-mode", "standard"],
        stdin=slave, stdout=slave, stderr=slave, env={**os.environ, "TERM": "xterm-256color", "XDG_CONFIG_HOME": directory},
    )
    captured = bytearray()
    checkpoint = 0

    def until(needle, timeout=30):
        target = needle.encode()
        deadline = time.monotonic() + max(timeout, float(os.environ.get("LOCALE_EDITOR_TEST_TIMEOUT", "0")))
        start = checkpoint
        while time.monotonic() < deadline:
            if target in re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', captured[start:]):
                return
            if select.select([master], [], [], 0.1)[0]:
                captured.extend(os.read(master, 65536))
                if target in re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', captured[start:]):
                    return
            if process.poll() is not None:
                break
        raise AssertionError(f"Did not see {needle!r}. Tail: {captured[-4000:]!r}")

    def send(value):
        global checkpoint
        checkpoint = len(captured)
        os.write(master, value.encode())

    def wait_exit(timeout=10):
        deadline = time.monotonic() + timeout
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                captured.extend(os.read(master, 65536))
        if process.poll() is None:
            raise AssertionError(f"TUI did not exit. Tail: {captured[-2000:]!r}")
        return process.returncode

    def capture(name):
        destination = os.environ.get("LOCALE_EDITOR_CAPTURE_DIR")
        if not destination:
            return
        while select.select([master], [], [], 0.15)[0]:
            captured.extend(os.read(master, 65536))
        text = captured.decode("utf-8", errors="replace")
        frame = text[text.rfind("\x1b[?25l\x1b[H"):]
        folder = pathlib.Path(destination)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / (name + ".json")).write_text(json.dumps({"columns": 120, "rows": 32, "ansi": frame}))

    try:
        until("LINUX LOCALE EDITOR")
        if sys.platform.startswith("linux"):
            until("Examples: glibc")
            assert b"Oct" in captured, "Formatted date example is not visible on the main panel"
        assert b"\x1b[0;37;44m" in captured, "MC-style blue panel is missing"
        capture("main")
        # Standard Left/Right does not switch panels. Tab does; Enter opens presets.
        send("\x1b[C\t\x1b[B\r")
        until("Formatted example")
        capture("date-presets")
        send("\x1bOS")  # F4 opens Custom from the preset popup
        until("Enter: accept")
        send("\x15%Y-%m-%d\r")
        until("Updated Date format")
        if sys.platform.startswith("linux"):
            until("Examples: glibc")
        # Currency-symbol popup: includes Unicode data, supports name search, and selection persists.
        send("\t\x1b[B\x1b[B\t\x1b[B\r")
        until("Formatted example")
        capture("currency-symbols")
        send("EURO SIGN")
        until("EURO SIGN")
        send("\r")
        until("Selected Currency symbol")
        if sys.platform.startswith("linux"):
            until("Examples: glibc")
        send("\x1bo")  # Alt+O opens the Options drop-down
        until("Cursor behavior")
        send("c")
        until("Standard cursor behavior")
        send("\x1b[B\r")
        until("Saved cursor mode: legacy")
        send("s")
        until("Save project")
        send("\x1b[F" + "\x7f" * 200 + str(saved) + "\r")
        until("Saved " + str(saved))
        send("q")
        assert wait_exit() == 0
        restored = termios.tcgetattr(slave)
        # Darwin marks pending input for retyping after returning to canonical mode.
        # PENDIN is kernel bookkeeping, not a terminal configuration change.
        restored[3] &= ~getattr(termios, "PENDIN", 0)
        original[3] &= ~getattr(termios, "PENDIN", 0)
        assert restored == original, f"TUI did not restore terminal flags: before={original!r}, after={restored!r}"
        project = json.loads(saved.read_text())
        assert project["sections"]["LC_TIME"]["overrides"]["d_fmt"] == {"text": {"_0": "%Y-%m-%d"}}
        assert project["sections"]["LC_MONETARY"]["overrides"]["currency_symbol"] == {"text": {"_0": "€"}}
        preferences = json.loads((pathlib.Path(directory) / "linux-locale-editor/preferences.json").read_text())
        assert preferences["cursorMode"] == "legacy"
        assert project["sourceFingerprints"], "Source fingerprints were not saved"
        assert b"\x1b[?1049h" in captured, "Alternate screen was not entered"
        print("TUI PTY test passed: MC colors, inline examples, presets/Custom, Unicode picker, cursor options, save and restoration.")
    finally:
        if process.poll() is None:
            process.send_signal(signal.SIGTERM)
            try:
                wait_exit()
            except AssertionError:
                process.kill()
                process.wait(timeout=5)
        os.close(master)
        os.close(slave)
