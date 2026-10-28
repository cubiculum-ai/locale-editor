#!/usr/bin/env python3
"""Postal/metadata UI and per-user install-only flow; no real profile or system default changes."""
import json
import pathlib
import sys
import tempfile
from tui_harness import TUI

binary = str(pathlib.Path(sys.argv[1]).resolve())
F10 = '\x1b[21~'

with tempfile.TemporaryDirectory(prefix='locale-postal-install-') as directory:
    root = pathlib.Path(directory)
    app = TUI(binary, directory, arguments=['--name', 'en_US.UTF-8@postal_ui_test'])
    def click(text):
        lines = app.text(text)
        x, y = app.position(lines, text)
        app.click(x + 1, y)
    try:
        app.ready()
        app.click(5, 9)  # Address
        app.text('Postal address format:')
        app.click(40, 5)
        app.text('Formatted postal address')
        app.send('\x1bOS')  # F4 Custom
        app.text('Custom: Postal address format')
        pattern = '%n%N%s %h%N%z %T%N%c'
        app.send('\x15' + pattern)
        app.text('Alex Example')
        app.send('\r')
        app.text('Updated Postal address format'); app.ready()
        app.click(5, 14)  # Metadata
        app.text('Title:')
        app.send('\t\x1b[B\x1bOS')  # choose title, F4
        app.text('Custom: Title')
        app.send('\x15My postal locale\r')
        app.text('Updated Title'); app.ready()
        app.send('s')
        app.text('Directory:')
        saved = root / 'postal.json'
        app.send('\x15' + str(saved) + '\r')
        app.text('Saved ' + str(saved)); app.ready()
        project = json.loads(saved.read_text())
        assert project['sections']['LC_ADDRESS']['overrides']['postal_fmt'] == {'text': {'_0': pattern}}
        assert project['sections']['LC_IDENTIFICATION']['overrides']['title'] == {'text': {'_0': 'My postal locale'}}
        if sys.platform.startswith('linux'):
            app.send('\x1bl')
            app.text('Install and select…')
            app.send('t')
            app.text('Current user')
            # Default scope is per-user. Choose install-only so tests do not modify real shell profiles.
            app.send('\r')
            app.text('Install and select')
            app.send('\x1b[B\r')
            app.text('Review installation')
            app.send('\r')
            app.text('Confirm installation')
            app.send('\x1b[B\r')
            app.text('Locale installation complete')
            destination = root / 'data/linux-locale-editor/locales/en_US.UTF-8@postal_ui_test'
            assert (destination / 'LC_ADDRESS').exists()
            assert (destination / 'LC_IDENTIFICATION').exists()
            assert not (root / 'environment.d').exists()
            assert not (root / 'linux-locale-editor/activate.sh').exists()
            app.send(F10); app.ready()
            # The system choice is present; cancel before any elevated operation.
            app.send('\x1bl'); app.text('Install and select…'); app.send('t')
            app.text('System-wide'); app.send('\x1b[B\r')
            app.text('Install locale · activation'); app.send(F10); app.ready()
        app.send('q')
        assert app.wait_exit() == 0
    finally:
        app.close()

print('Postal/install PTY test passed: multiline preview, metadata editing, save and isolated per-user install-only flow.')
