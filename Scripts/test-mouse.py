#!/usr/bin/env python3
"""End-to-end terminal mouse reports, including SSH-style fragmentation and wide coordinates."""
import json
import pathlib
import signal
import sys
import tempfile
import time
from tui_harness import TUI

binary = str(pathlib.Path(sys.argv[1]).resolve())

with tempfile.TemporaryDirectory(prefix='locale-mouse-test-') as directory:
    app = TUI(binary, directory)
    try:
        app.ready()
        assert b'\x1b[?1000h' in app.output and b'\x1b[?1006h' in app.output
        # Section click and field click (including its example row) open the correct popup.
        app.click(6, 5)
        app.text('Currency symbol:')
        app.click(40, 6)
        first = app.text('Formatted example')
        assert 'U+00A4' in first[6], 'Generic currency should precede national symbols'
        # Clicking the panel outside a modal cannot switch sections behind it.
        app.click(0, 3)
        app.text('Formatted example')
        app.wheel(45, 10)
        app.until(lambda lines: 'U+00A3' in lines[6])
        app.wheel(45, 10, down=False)
        app.until(lambda lines: 'U+00A4' in lines[6])
        app.send('EURO SIGN')
        matches = app.until(lambda lines: any('Search: EURO SIGN' in line for line in lines) and any('U+20AC' in line for line in lines))
        _, row = app.position(matches, 'U+20AC')
        app.click(10, row)
        app.text('Selected Currency symbol')
        app.ready()
        # Wheel movement changes the visible field list immediately, not just its highlight.
        app.wheel(45, 12)
        app.until(lambda lines: 'Grouping separator:' in lines[5])
        app.wheel(45, 12, down=False)
        app.until(lambda lines: 'Currency symbol:' in lines[5])
        app.click(5, 3)
        app.text('Date format:')
        # An SGR report split across reads must never appear as literal text or keyboard commands.
        app.send('\x1b[<0;41;')
        time.sleep(0.25)
        app.send('6M\x1b[<0;41;6m')
        app.text('Formatted example')
        app.click(35, 31)  # exact left boundary of F4, even in a modal
        app.text('Custom: Date format')
        app.send('\x15A界B')
        edit = app.text('A界B')
        x, row = app.position(edit, 'A界B')
        app.click(x + 3, row)  # after the two-cell character
        app.send('X')
        app.text('A界XB')
        app.send('\x15%Y-%m-%d')
        app.text('%Y-%m-%d')
        app.click(11, 31)  # exact left boundary of modal F2 OK
        app.text('Updated Date format')
        app.ready()
        # Source-row click changes the parent while retaining the explicit date override.
        app.click(40, 3)
        app.text('existing field overrides are retained')
        parent = 'en_GB' if sys.platform.startswith('linux') else 'demo_de'
        app.send(parent)
        matches = app.text('Search: ' + parent)
        row = next(i for i, line in enumerate(matches) if 6 <= i <= 24 and parent in line)
        app.click(10, row)
        app.text('explicit overrides retained')
        app.ready()
        # Preview pager scrolling and context-specific F10 must close the pager, not the app.
        if sys.platform.startswith('linux'):
            app.click(47, 31)
            first_page = app.text('Preview:')
            app.wheel(40, 10)
            app.until(lambda lines: lines[3] != first_page[3])
            app.click(107, 31)
            app.text('LINUX LOCALE EDITOR')
        # Recompute targets after resize; SGR coordinates beyond X10's 223-cell limit work.
        app.resize(300, 36)
        app.until(lambda lines: len(lines) == 36)
        app.click(250, 5)
        app.text('Formatted example')
        app.click(269, 35)
        app.text('LINUX LOCALE EDITOR')
        app.click(29, 35)  # first cell of F2 at the new width
        app.text('Save project')
        saved = pathlib.Path(directory) / 'mouse.json'
        app.send('\x15' + str(saved))
        lines = app.text(str(saved))
        x, row = app.position(lines, '[ Save ]')
        app.click(x + 2, row)
        app.text('Saved ' + str(saved))
        # The release event from the save dialog must not activate any background action.
        assert app.process.poll() is None
        app.click(269, 35)
        assert app.wait_exit() == 0
        project = json.loads(saved.read_text())
        assert project['sections']['LC_TIME']['source'] == parent
        assert project['sections']['LC_TIME']['overrides']['d_fmt'] == {'text': {'_0': '%Y-%m-%d'}}
        assert project['sections']['LC_MONETARY']['overrides']['currency_symbol'] == {'text': {'_0': '€'}}
    finally:
        app.close()
    # Signal cleanup must turn reporting off too; otherwise the user's shell receives click garbage.
    app = TUI(binary, directory)
    try:
        app.ready()
        app.process.send_signal(signal.SIGTERM)
        assert app.wait_exit() == 128 + signal.SIGTERM
    finally:
        app.close()

print('Mouse PTY test passed: sections, fields, source/choice popups, wheel, modal isolation, Unicode caret, split reports, resize, function bar and cleanup.')
