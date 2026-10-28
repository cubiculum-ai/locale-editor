"""Shared PTY harness for keyboard/mouse/menu integration tests; no external packages."""
import fcntl
import os
import pathlib
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import unicodedata

repo = pathlib.Path(__file__).resolve().parent.parent
ansi = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')

class TUI:
    def __init__(self, binary, directory, arguments=None, force_tui=True):
        self.master, self.slave = pty.openpty()
        self.resize(120, 32)
        self.original = termios.tcgetattr(self.slave)
        base = 'en_US' if sys.platform.startswith('linux') else 'demo_en'
        self.process = subprocess.Popen(
            [binary] + (['--tui'] if force_tui else []) + ['--sources', str(repo / 'Examples/locales'), '--base', base, '--cursor-mode', 'standard'] + (arguments or []),
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
            env={**os.environ, 'TERM': 'xterm-256color', 'XDG_CONFIG_HOME': directory, 'XDG_DATA_HOME': str(pathlib.Path(directory) / 'data')},
        )
        self.output = bytearray()
        self.checkpoint = 0

    def resize(self, columns, rows):
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, columns, 0, 0))
        self.columns, self.rows = columns, rows

    def read(self, timeout=0.1):
        if select.select([self.master], [], [], timeout)[0]:
            self.output.extend(os.read(self.master, 262144))

    def send(self, data):
        self.checkpoint = len(self.output)
        os.write(self.master, data.encode() if isinstance(data, str) else data)

    def click(self, x, y):
        self.send(f'\x1b[<0;{x+1};{y+1}M\x1b[<0;{x+1};{y+1}m')

    def wheel(self, x, y, down=True):
        self.send(f'\x1b[<{65 if down else 64};{x+1};{y+1}M')

    def frame(self):
        text = self.output[self.checkpoint:].decode('utf-8', errors='replace')
        frames = text.split('\x1b[?25l\x1b[H')[1:]
        for frame in reversed(frames):
            if '\x1b[0m' in frame:
                return ansi.sub('', frame.split('\x1b[0m')[0]).split('\r\n')
        return []

    def until(self, predicate, timeout=40):
        deadline = time.monotonic() + max(timeout, float(os.environ.get("LOCALE_EDITOR_TEST_TIMEOUT", "0")))
        while time.monotonic() < deadline:
            lines = self.frame()
            if lines and predicate(lines):
                return lines
            if self.process.poll() is not None:
                break
            self.read()
        failure = repo / '.build' / f'tui-failure-{self.process.pid}.ansi'
        failure.parent.mkdir(parents=True, exist_ok=True)
        failure.write_bytes(self.output)
        raise AssertionError(f'Mouse interaction did not reach expected screen. Exit: {self.process.poll()}; capture: {failure}. Last frame: {self.frame()!r}')

    def text(self, value):
        return self.until(lambda lines: any(value in line for line in lines))

    def ready(self):
        marker = 'Examples: glibc' if sys.platform.startswith('linux') else 'Formatted examples require Linux'
        # A dialog can leave the editor's status visible behind it. Require the main
        # function bar as well, so subsequent input cannot race with a closing modal.
        return self.until(lambda lines: any(marker in line for line in lines)
                          and '9Menu' in lines[-1] and '10Quit' in lines[-1])

    @staticmethod
    def position(lines, text):
        for row, line in enumerate(lines):
            index = line.find(text)
            if index >= 0:
                x = sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in line[:index])
                return x, row
        raise AssertionError(f'{text!r} is not visible in {lines!r}')

    def wait_exit(self):
        deadline = time.monotonic() + 10
        while self.process.poll() is None and time.monotonic() < deadline:
            self.read()
        if self.process.poll() is None:
            raise AssertionError('Application did not exit')
        self.read(0)
        restored = termios.tcgetattr(self.slave)
        restored[3] &= ~getattr(termios, 'PENDIN', 0)
        self.original[3] &= ~getattr(termios, 'PENDIN', 0)
        assert restored == self.original, 'Terminal attributes were not restored'
        assert b'\x1b[?1006l' in self.output and b'\x1b[?1000l' in self.output, 'Mouse reporting was not disabled'
        return self.process.returncode

    def close(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.wait_exit()
            except AssertionError:
                self.process.kill()
                self.process.wait(timeout=5)
        os.close(self.master)
        os.close(self.slave)
