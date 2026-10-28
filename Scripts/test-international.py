#!/usr/bin/env python3
"""Standards, Names, POSIX responses, character probes and output actions via real PTY."""
import json
import pathlib
import sys
import tempfile
from tui_harness import TUI

binary = str(pathlib.Path(sys.argv[1]).resolve())
F4, F10 = '\x1bOS', '\x1b[21~'
with tempfile.TemporaryDirectory(prefix='locale-international-ui-') as directory:
    root = pathlib.Path(directory)
    app = TUI(binary, directory, arguments=['--name', 'en_US.UTF-8@international_ui_test'])
    try:
        app.ready()
        app.click(40, 5)
        app.text('International standard · ISO 8601')
        if sys.platform.startswith('linux'):
            app.text('2026-10-27')
        app.send('\r'); app.text('Selected Date format'); app.ready()
        app.click(5, 10)  # Names
        app.text('Name format:')
        app.click(40, 5)
        app.text('Given and family names')
        app.send('\r'); app.text('Selected Name format'); app.ready()
        app.send(F4); app.text('Custom: Name format')
        app.send('\x15%f, %g%t%m')
        app.text('Example, Alex Robin')
        app.send('\r'); app.text('Updated Name format'); app.ready()
        app.click(5, 8)  # Yes / no
        app.text('Yes label:')
        app.click(40, 9)
        app.text('Yes expression')
        if sys.platform.startswith('linux'):
            app.text('Matches:')
        app.send(F4); app.text('Custom: Yes expression')
        app.send('\x15^([yY]es|[jJ]a)$')
        if sys.platform.startswith('linux'):
            app.text('Matches: yes')
        app.send('\r'); app.text('Updated Yes expression'); app.ready()
        app.click(5, 13)  # Character handling
        app.text('Character profile:')
        if sys.platform.startswith('linux'):
            app.click(40, 5); app.text('International character repertoire')
            app.send('\r'); app.text('Character profile: i18n'); app.ready()
            app.click(40, 7); app.text('Test characters')
            app.send('\x15äI0!\r')
            app.text('Character behavior · compiled glibc')
            app.text('U+0030'); app.text('digit')
            app.send(F10); app.ready()
        app.send('\x1bl'); app.text('International conventions…'); app.send('c')
        app.text('International conventions · scope'); app.send('\r')
        app.text('Apply international conventions'); app.send('\r')
        app.text('Applied international conventions'); app.ready()
        app.click(5, 6); app.text('Paper size: A4')
        app.send('u'); app.text('Undo.'); app.ready()
        app.send('y'); app.text('Redo.'); app.ready()
        app.send('s'); app.text('Directory:')
        saved = root / 'international.json'
        app.send('\x15' + str(saved) + '\r'); app.text('Saved ' + str(saved)); app.ready()
        sections = json.loads(saved.read_text())['sections']
        assert sections['LC_MONETARY']['overrides']['currency_symbol'] == {'text': {'_0': '¤'}}
        assert sections['LC_MONETARY']['overrides']['mon_thousands_sep'] == sections['LC_NUMERIC']['overrides']['thousands_sep']
        assert sections['LC_MONETARY']['overrides']['mon_grouping'] == sections['LC_NUMERIC']['overrides']['grouping']
        assert sections['LC_TIME']['overrides']['week'] == {'integers': {'_0': [7, 19971130, 4]}}
        assert sections['LC_NAME']['overrides']['name_fmt'] == {'text': {'_0': '%f, %g%t%m'}}
        assert sections['LC_MESSAGES']['overrides']['yesexpr'] == {'text': {'_0': '^([yY]es|[jJ]a)$'}}
        assert sections['LC_TELEPHONE']['overrides']['tel_int_fmt'] == {'text': {'_0': '+%c%a%l'}}
        if sys.platform.startswith('linux'):
            app.send('b'); app.text('Compile locale · output directory')
            compiled = root / 'compiled'
            app.send('\x15' + str(compiled) + '\r'); app.text('Compiled successfully')
            assert (compiled / 'en_US.UTF-8@international_ui_test/LC_CTYPE').exists()
            app.send(F10); app.ready()
            # Mouse selects the finish action. XDG paths isolate install-only from real defaults.
            app.send('a'); lines = app.text('Compile and install only')
            x, y = app.position(lines, 'Compile and install only'); app.click(x + 1, y)
            app.text('Current user'); app.send('\r')
            app.text('Install locale · activation'); app.send('\r')  # install-only is preselected
            app.text('Review installation'); app.send('\r')
            app.text('Confirm installation'); app.send('\x1b[B\r')
            app.text('Locale installation complete')
            installed = root / 'data/linux-locale-editor/locales/en_US.UTF-8@international_ui_test'
            assert (installed / 'locale.src').exists() and (installed / 'LC_NAME').exists()
            assert not (root / 'linux-locale-editor/activate.sh').exists()
            app.send(F10); app.ready()
        app.send('q'); assert app.wait_exit() == 0
    finally:
        app.close()
print('International PTY test passed: standard-first presets, names, responses, character probe, atomic conventions, directory compilation and isolated install-only.')
