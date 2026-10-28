#!/usr/bin/env python3
"""Exercise real drop-down menus through keyboard, mouse, resize and command side effects."""
import json
import pathlib
import sys
import tempfile
from tui_harness import TUI

binary = str(pathlib.Path(sys.argv[1]).resolve())
F9 = '\x1b[20~'
F10 = '\x1b[21~'

with tempfile.TemporaryDirectory(prefix='locale-menu-test-') as directory:
    app = TUI(binary, directory)

    def click_text(text):
        lines = app.text(text)
        x, y = app.position(lines, text)
        app.click(x, y)

    def menu(letter, text):
        app.send('\x1b' + letter)
        return app.text(text)

    try:
        app.ready()
        # F9 and arrows wrap between menus; unavailable entries stay disabled.
        app.send(F9)
        app.text('Select section…')
        app.send('\x1b[D')
        app.text('Unicode data license')
        app.send('\x1b[C')
        app.text('Select section…')
        app.send('f')  # heading mnemonic when no item in the current menu uses it
        app.text('Save project as…')
        app.send('\t')
        app.text('Choose preset…')
        app.send('c')
        app.text('Select an editable field first.')
        assert 'Custom: ' not in '\n'.join(app.frame())
        # Clicking another heading switches menus, and clicking Save invokes the actual command.
        app.click(11, 0)
        app.text('Save project as…')
        click_text('Save project…')
        app.text('Directory:')
        app.send(F10)
        app.ready()
        # An outside click dismisses the menu without activating Currency behind it.
        menu('f', 'Save project as…')
        app.click(4, 5)
        lines = app.ready()
        assert 'Date format:' in '\n'.join(lines)
        assert 'Currency symbol:' not in '\n'.join(lines)
        # Ctrl-C cancels an open menu, while preserving the running editor.
        menu('e', 'Choose preset…')
        app.send('\x03')
        app.ready()
        assert app.process.poll() is None
        # Field availability updates when a field is selected. Item mnemonics execute commands.
        app.send('\t\x1b[B')
        app.text('d_fmt =')
        menu('e', 'Custom value…')
        app.send('c')
        app.text('Custom: Date format')
        app.send('\x15%Y-%m-%d\r')
        app.text('Updated Date format')
        app.ready()
        menu('e', 'Undo')
        app.send('u')
        app.text('Undo.')
        app.ready()
        menu('e', 'Redo')
        app.send('d')
        app.text('Redo.')
        app.ready()
        assert '%Y-%m-%d' in '\n'.join(app.frame())
        # Save As and Export affect the filesystem through the same paths as keyboard shortcuts.
        menu('f', 'Save project as…')
        app.send('a')
        app.text('Directory:')
        saved = pathlib.Path(directory) / 'menu-project.json'
        app.send('\x15' + str(saved) + '\r')
        app.text('Saved ' + str(saved))
        project = json.loads(saved.read_text())
        assert project['sections']['LC_TIME']['overrides']['d_fmt'] == {'text': {'_0': '%Y-%m-%d'}}
        menu('f', 'Export locale source…')
        app.send('e')
        app.text('Directory:')
        exported = pathlib.Path(directory) / 'menu-locale.src'
        app.send('\x15' + str(exported) + '\r')
        app.text('Exported ' + str(exported))
        assert 'd_fmt "%Y-%m-%d"' in exported.read_text()
        # Options remains accessible by mouse and keyboard after F9 becomes the menu key.
        app.click(25, 0)
        click_text('Cursor behavior…')
        app.text('Standard cursor behavior')
        app.send('\x1b[B\r')
        app.text('Saved cursor mode: legacy')
        menu('o', 'Cursor behavior…')
        app.send('c')
        app.text('Legacy cursor behavior')
        app.send('\x1b[A\r')
        app.text('Saved cursor mode: standard')
        preferences = json.loads((pathlib.Path(directory) / 'linux-locale-editor/preferences.json').read_text())
        assert preferences['cursorMode'] == 'standard'
        # Help/license commands and F10 cancellation do not quit the application.
        menu('h', 'Unicode data license')
        app.send('l')
        app.text('UNICODE LICENSE V3')
        app.send(F10)
        app.ready()
        # Wheel changes the selected command, then a mouse click executes the item under the pointer.
        menu('f', 'Save project as…')
        app.wheel(15, 3)
        app.text('Save project as…')
        click_text('View generated source')
        app.text('Generated localedef source')
        app.send(F10)
        app.ready()
        # Menu hit targets stay aligned after resize, and opening by the F9 bar also works.
        app.click(95, 31)
        app.text('Save project as…')
        app.resize(80, 24)
        app.until(lambda lines: len(lines) == 24)
        app.click(34, 0)
        app.text('Unicode data license')
        click_text('Keyboard and mouse help')
        app.text('Keyboard reference')
        app.send(F10)
        app.ready()
        app.resize(120, 32)
        app.until(lambda lines: len(lines) == 32)
        # Locale > Select section is a real action, not a decorative entry.
        menu('l', 'Select section…')
        app.send('s')
        app.text('Search:')
        app.send('Currency')
        app.text('Search: Currency')
        app.send('\r')
        app.text('Currency symbol:')
        # Opening a project resets editor state as before.
        menu('f', 'Open project…')
        app.send('o')
        app.text('Directory:')
        app.send('\x15' + str(saved) + '\r')
        app.text('Opened ' + str(saved))
        app.ready()
        # Menu Quit must retain the unsaved-change confirmation, including cancellation.
        menu('l', 'Rename locale…')
        app.send('r')
        app.text('Locale name')
        app.send('\x15en_US.UTF-8@menu_test\r')
        app.ready()
        menu('f', 'Quit')
        app.send('q')
        app.text('Discard unsaved changes?')
        app.send('\x1b')
        app.ready()
        assert '[modified]' in '\n'.join(app.frame())
        menu('f', 'Quit')
        click_text('Quit')
        app.text('Discard unsaved changes?')
        app.send('yes\r')
        assert app.wait_exit() == 0
    finally:
        app.close()

print('Menu PTY test passed: keyboard/mouse navigation, disabled commands, mnemonics, resize, save/export/open, options/help and guarded quit.')
