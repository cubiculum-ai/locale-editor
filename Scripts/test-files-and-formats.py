#!/usr/bin/env python3
"""Exercise named paper/phone presets and real directory-based file dialogs."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
from tui_harness import TUI

binary = str(pathlib.Path(sys.argv[1]).resolve())
repo = pathlib.Path(__file__).resolve().parent.parent
F2, F7, F8, F10 = '\x1bOQ', '\x1b[18~', '\x1b[19~', '\x1b[21~'

with tempfile.TemporaryDirectory(prefix='locale-files-') as directory:
    root = pathlib.Path(directory)
    child = root / 'alpha child'
    child.mkdir()
    (root / 'βeta').mkdir()
    (child / 'inside marker.txt').write_text('directory navigation marker')
    for number in range(25):
        (root / f'file-{number:02}.txt').write_text('fixture')
    seed = root / 'seed.json'
    base = 'en_US' if sys.platform.startswith('linux') else 'demo_en'
    subprocess.run([binary, 'new', '--sources', str(repo / 'Examples/locales'), '--base', base,
                    '--name', 'en_US.UTF-8@file_test', '--output', str(seed)], check=True, stdout=subprocess.DEVNULL)
    shutil.copyfile(seed, root / '.hidden.json')
    app = TUI(binary, str(root / 'config'), arguments=['--project', str(seed)])

    def click(text):
        lines = app.text(text)
        x, y = app.position(lines, text)
        app.click(x + 1, y)

    def menu(letter, command, item):
        app.send('\x1b' + letter)
        app.text(item)
        app.send(command)

    try:
        app.ready()
        app.click(5, 6)  # Paper section
        app.text('Paper size:')
        app.click(40, 5)
        app.text('Named sizes')
        app.send('Fax-safe')
        app.text('Search: Fax-safe')
        app.send('\r')
        app.text('Selected Fax-safe')
        app.ready()
        app.send('u'); app.text('Undo.'); app.ready()
        assert 'Paper size: Fax-safe' not in '\n'.join(app.frame())
        app.send('y'); app.text('Redo.'); app.ready()
        assert 'Paper size: Fax-safe' in '\n'.join(app.frame())
        app.click(5, 11)  # Telephone section
        app.text('International format:')
        app.click(40, 5)
        app.text('Formatted example')
        app.send('+%c(%a)%l')
        app.text('Search: +%c(%a)%l')
        app.send('\r')
        app.text('Selected International format')
        app.ready()
        assert '+%c(%a)%l' in '\n'.join(app.frame())
        # Save As opens a browser in the current project's directory.
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        app.send('\x1bl\x1b[H')  # reveal the directories above the preselected existing filename
        click('/ alpha child')
        app.text('inside marker.txt')
        click('[ Save ]')  # keep the suggested name while saving inside the entered folder
        app.text('Saved ' + str(child / 'seed.json')); app.ready()
        assert (child / 'seed.json').exists()
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        click('[ Up ]')
        app.text('seed.json') if 'seed.json' in '\n'.join(app.frame()) else app.text('/ alpha child')
        app.send('\x1bn\x15named-output.json')
        app.text('named-output.json')
        click('[ Save ]')
        saved = root / 'named-output.json'
        app.text('Saved ' + str(saved))
        app.ready()
        data = json.loads(saved.read_text())
        assert data['sections']['LC_PAPER']['overrides'] == {'height': {'integer': {'_0': 279}}, 'width': {'integer': {'_0': 210}}}
        assert data['sections']['LC_TELEPHONE']['overrides']['tel_int_fmt'] == {'text': {'_0': '+%c(%a)%l'}}
        # Ordinary Save writes the established file directly.
        app.send(F2)
        app.text('Saved ' + str(saved)); app.ready()
        assert not any('Directory:' in line for line in app.frame())
        # Export supports directory creation and a filename containing spaces.
        menu('f', 'e', 'Export locale source…')
        app.text('Directory:')
        app.send(F7)
        app.text('New directory')
        app.send('Exports\r')
        app.text('Directory:')
        app.send('\x1bn\x15custom locale.src')
        app.text('custom locale.src')
        click('[ Export ]')
        exported = root / 'Exports/custom locale.src'
        app.text('Exported ' + str(exported)); app.ready()
        source = exported.read_text()
        assert 'width 210' in source and 'height 279' in source and 'tel_int_fmt "+%c(%a)%l"' in source
        # Failed navigation and missing-file selection retain the browser.
        menu('f', 'o', 'Open project…')
        app.text('Directory:')
        app.send('\x0c\x15' + str(root / 'missing') + '\r')
        app.text('Not a directory:')
        app.send('\x1bp\x15' + str(root) + '\r')
        app.text('/ alpha child')
        app.send('\x1bn\x15missing.json\r')
        app.text('existing, readable regular file')
        # Wheel scrolling moves the file list; Hidden exposes an otherwise omitted project.
        app.wheel(50, 12)
        app.until(lambda lines: '/ ..' not in lines[7])
        app.wheel(50, 12, down=False)
        app.until(lambda lines: '/ ..' in lines[7])
        app.send(F8)
        app.text('.hidden.json')
        click('.hidden.json')
        click('[ Open ]')
        app.text('Opened ' + str(root / '.hidden.json')); app.ready()
        # Save As cancellation must not overwrite an existing project.
        original = saved.read_bytes()
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        app.send('\x15' + str(saved) + '\r')
        app.text('Replace existing file?')
        app.send('\x1b'); app.ready()
        assert saved.read_bytes() == original
        # Enter defaults to Cancel; an explicit Replace click is required to overwrite.
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        app.send('\x15' + str(saved) + '\r')
        app.text('Replace existing file?')
        app.send('\r'); app.ready()
        assert saved.read_bytes() == original
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        app.send('\x15' + str(saved) + '\r')
        app.text('Replace existing file?')
        click('[ Replace ]')
        app.text('Saved ' + str(saved)); app.ready()
        assert json.loads(saved.read_text())['sections']['LC_PAPER']['overrides'] == {}
        # Keyboard list navigation enters a directory and goes back without using a path prompt.
        menu('f', 'o', 'Open project…')
        app.text('Directory:')
        app.send('\x1bl\x1b[H\x1b[B\x1b[C')
        app.text('inside marker.txt')
        app.send('\x1b[D')
        app.text('/ alpha child')
        app.send('seed')
        app.text('Find: seed')
        app.send('\r')
        app.text('Opened ' + str(seed)); app.ready()
        # Dialog targets remain aligned when resized, and cancellation leaves the project intact.
        menu('f', 'a', 'Save project as…')
        app.text('Directory:')
        app.resize(80, 24)
        app.until(lambda lines: len(lines) == 24)
        click('[ Cancel ]')
        app.ready()
        app.send(F10)
        assert app.wait_exit() == 0
    finally:
        app.close()

print('File/preset PTY test passed: named paper and phone, atomic undo, directory navigation, mouse/keyboard, hidden files, mkdir, overwrite cancellation and resize.')
