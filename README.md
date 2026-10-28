# Linux Locale Editor

A Swift application for composing UTF-8 glibc locales, with a native GTK graphical editor for Xfce and an MC-style terminal interface. Both frontends share the same project model, field schema, presets, validation, previews, and installation backend. KDE System Settings integration remains a possible future extension.

## Signed APT repository

Install and update through the [signed GitHub Pages APT repository](https://cubiculum-ai.github.io/locale-editor/). Follow the [key verification and installation instructions](docs/apt.md). APT selects amd64 or arm64 automatically. Install `locale-editor-gui` for GTK plus terminal mode, or `locale-editor-tui` for a headless system.

The application is [MIT-licensed](LICENSE). Third-party runtime and data notices are under [ThirdParty](ThirdParty/NOTICE.txt).

## Debian / apt packages

Two mutually exclusive packages are built:

| Package | Interfaces | Graphical dependencies |
| --- | --- | --- |
| `locale-editor-gui` | Native GTK GUI plus the full TUI and CLI | GTK 3 and its system libraries |
| `locale-editor-tui` | TUI and CLI | None; no GTK, Qt, X11 or Wayland linkage |

Each edition is built for **amd64 and arm64**, producing four files. Build each architecture on a native Linux host with the required toolchain and development libraries.

Install **one** package matching `dpkg --print-architecture`, for example on an amd64 machine:

```sh
sudo apt install ./dist/locale-editor-gui_0.2.0-2_amd64.deb
# Or switch to the terminal-only edition:
sudo apt install ./dist/locale-editor-tui_0.2.0-2_amd64.deb
```

Apt removes the other edition when switching. Both provide `locale-editor` and install the same executable path. They do not alter your locale defaults during package installation/removal. Saved projects and installed custom locales are not package-owned and are retained.

| Command | GUI package | Terminal-only package |
| --- | --- | --- |
| `locale-editor` or `locale-edit` | Open GTK GUI | Open TUI |
| `locale-editor-tui` or `locale-edit-tui` | Open TUI | Open TUI |
| `locale-editor --gui` | Open GTK GUI | Explain that GUI package is needed |
| `locale-editor --tui` | Open TUI | Open TUI |
| `locale-editor export`, `compile`, `preview`, etc. | Run CLI operation without opening a display | Same |

Aliases are symlinks to the same executable within each package. Explicit interface flags override the invocation-name default. CLI operations and internal workers dispatch before GTK/terminal initialization. `--version` reports the installed edition.

The GUI package registers **Linux Locale Editor** in Xfce Settings Manager and the desktop's Settings applications menu. It opens a native GTK window with normal theme, accessibility, keyboard navigation, and file dialogs. Select a section on the left, then double-click a field for searchable presets or use **Custom**. **Edit → International conventions** applies the coordinated preset. **File → Install and select** offers personal/system scope. Ctrl+S saves, Ctrl+O opens, Ctrl+Z undoes, and F4 edits the selected field.

System installation uses `pkexec` with an application-specific polkit policy. The desktop's running authentication agent displays the administrator prompt; on terminal sessions pkexec can supply a text agent. GUI authentication never runs the editor as root and never passes passwords through the app. A desktop polkit authentication agent must be running; install the one appropriate for your desktop if absent. Per-user installation needs no administrator authentication. The policy requires administrator authentication under the machine's policy and does not retain it by default.

For arm64 machines, use the corresponding `_arm64.deb` files. Packages embed the Swift runtime but use distribution-provided libraries and locale data. Their minimum library versions are calculated with `dpkg-shlibdeps`; a package built on current Kali is not a universal binary for every older Linux distribution. For broader compatibility, build on the oldest distribution you intend to support.

## Run on Linux

Building requires Swift 6.0 or newer. Running the release requires compatible Linux system libraries, glibc locale tools, and the distribution's locale **sources** and UTF-8 charmap. Having an entry in `locale -a` is not sufficient: compiled locales are not editable source documents.

On Debian/Ubuntu:

```sh
sudo apt-get install locales
bash Scripts/build-release.sh
./bin/locale-editor --base en_GB --name en_GB.UTF-8@personal
```

`swift run` is useful during development, but normal use is the executable directly. The release script embeds the Swift runtime and Foundation, checks its dynamic dependencies, and writes `bin/locale-editor`. A Swift compiler/runtime installation is not needed to run that release. It still requires compatible Linux system libraries, glibc locale tools (`localedef` and `locale`), and locale source data. A binary built on a newer glibc distribution is not automatically portable to older ones; broad distribution releases should be built on the oldest supported glibc baseline.

We retain glibc for authentic locale previews. Swift's fully static Linux SDK uses musl and would require a separate glibc preview helper for this application.

On Fedora the source data is provided by `glibc-locale-source`. Source directories can be specified explicitly, in priority order:

```sh
./bin/locale-editor --sources /path/to/custom/locales --base de_AT
```

The system `/usr/share/i18n/locales` directory is also searched when available. The catalog includes uncompiled source locales. Supplementary files such as transliteration tables remain available to the compiler without appearing as selectable locales.

### Native Linux verification

Run `bash Scripts/check-linux.sh` on the native Linux build host. It covers the core, runtime, terminal interactions and glibc previews. GUI and Debian-package checks are documented below.

The executable can be copied to a compatible Linux host without the project sources or Swift toolchain. See [Swift's Linux linking guidance](https://docs.swift.org/latest/documentation/swiftlinux/building/) for the runtime-linking distinction.

## Terminal keyboard controls

The interface uses Midnight Commander-style blue panels, cyan selections, bordered popups and a function-key bar. Use a terminal at least 70 columns wide and 22 rows high; 120 × 32 leaves more room for definitions and examples.

| Key | Action |
| --- | --- |
| Up / Down | Select section or field |
| Tab / Shift-Tab | Switch between sections and fields |
| Enter | Open source picker or choose a predefined field value |
| F4 | Edit the selected field as Custom text |
| `i` or `/` | Search sources for the current section |
| `r` | Reset the selected field to its inherited value |
| `u` / `y` | Undo / redo |
| `p` | Compile and show glibc previews |
| `w` | Set words for the sorting preview |
| `s` / `o` | Save / open a project |
| `n` | Rename the output locale |
| `v` / `e` | View / export generated locale source |
| `b` | Compile into a chosen output directory |
| `a` | Export / compile / activate, with personal or system install scope |
| `?` | Help |
| `q` / Ctrl-C | Quit, with a prompt for unsaved changes |
| F1 / F2 / F3 | Help / save / view source |
| F5 / F6 / F7 / F8 | Full preview / inherit / search / reset |
| F9 / F10 | Open menu bar / quit |

The top bar has functional **Locale, File, Edit, Options, and Help** drop-down menus. Click a heading, press F9, or use Alt+L/F/E/O/H to open one directly. Left/Right or Tab/Shift-Tab switches menus; Up/Down moves between available commands; Home/End selects the first/last available command. Enter or an underlined item letter runs a command. The mouse wheel moves the menu selection, and clicking an item runs it.

Esc, Ctrl-C, F9, F10, or an outside click closes an open menu without activating the panel behind it. F10 quits from the main screen. Unavailable actions are greyed out: field actions need a selected editable field, Undo/Redo depend on history, and compilation/previews depend on the runtime. Menu items display the existing shortcut keys and use the same execution paths, including overwrite and unsaved-change confirmations.

File includes Open, Save, Save As, source inspection/export, compilation, and Quit. Locale includes section selection, inheritance, renaming and previews. Cursor settings are under **Options → Cursor behavior**; Help also exposes the Unicode data license.

Open, Save As, first-time Save, Export, and Compile use directory-based file dialogs. Compile accepts an existing or new output directory; an empty name means the displayed directory, and F2/Compile accepts it. Directory entries still navigate with Enter or a click. Files and directories are listed with directories first; select a file by mouse or keyboard, or type its full path. Click a directory to enter it, or focus the list and press Enter/Right. Left/Backspace in the list or F6 goes up. Tab/Shift-Tab cycles directory, list and filename fields; Ctrl-L or Alt+P focuses the directory path, Alt+L the list, and Alt+N the filename. F2 accepts, F5 refreshes, F7 creates a directory, F8 toggles hidden entries, and F10 cancels. Up/Home buttons and mouse-wheel scrolling are available. Existing files are not overwritten without confirmation for Save As/Export; ordinary Save writes the current project file directly.

Mouse support is enabled automatically in compatible terminals, including over SSH. Click a section to focus it, a field or its example to open its choices, an inheritance row to choose a parent, and a popup entry to select it. The function-key bar is clickable; dialogs show only the actions that apply to that dialog. Text dialogs also have clickable OK/Cancel buttons and let you position the cursor with a click.

The mouse wheel scrolls the list under the pointer: sections, fields, popup choices, or the full preview/source/help viewer. Popup scrolling changes the visible rows immediately. Clicks outside a modal are ignored, and release events cannot activate the panel behind it. Keyboard navigation remains available. Most terminals support Shift-drag for their own text selection while application mouse reporting is active.

The TUI uses [xterm SGR mouse reports](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking) with a legacy report fallback. Reporting is turned off when the application exits, including handled termination signals. Terminal/protocol decoding and click targets remain in `LocaleEditorTUI`; the locale core has no mouse dependencies.

Escape followed by 1–9 or 0 is an alternative to F1–F10. In text dialogs, Left/Right moves the visible terminal cursor, Home/End moves to the start/end, Ctrl-U clears the line, and Ctrl-W removes the preceding word. Standard navigation is the default. Options → Cursor behavior can enable the original Left/Right pane switching, saved in `$XDG_CONFIG_HOME/linux-locale-editor/preferences.json` (normally `~/.config/linux-locale-editor/preferences.json`). `--cursor-mode standard|legacy` overrides the saved preference for a run.

Each editable field opens a searchable list of distinct definitions from all available locale source files, resolving inheritance and collecting the locales that use each value. The list shows the definition and a sample. Search matches definitions, samples, Unicode names and source locales. Select **Custom…**, or press F4, to enter a value freely. Custom date/time entry updates its sample while typing.

Currency-symbol choices combine all **67 Unicode 18.0 currency-symbol (`Sc`) characters** with the strings used by locale files, including multi-character symbols. Entries show the glyph, Unicode name/code point and a monetary example. Custom remains available. Font support determines whether a glyph is drawn; its code point/name remain visible. Unicode data is embedded in the executable; `locale-editor --license` displays its notice, also stored in `ThirdParty/UNICODE-LICENSE.txt`.

Text fields accept literal Unicode; quoting and localedef escaping are handled by the exporter. Weekday/month lists use `|` between entries. Grouping uses semicolons, for example `3;3` or `3;2`. International currency codes require a trailing space (`EUR `); an empty code and unspecified monetary sentinel values remain available where locale sources use them.

## Supported editing

Every glibc category has an independent parent selection. Structured field editors currently cover:

- Date/time formats, weekday/month names, AM/PM labels, first weekday/workday, and week definition.
- Numeric decimal separator, grouping separator and group sizes.
- Currency symbols, decimal places, separators, grouping, signs, placement and spacing.
- Named paper sizes, custom dimensions, and measurement system.
- International/domestic telephone display formats and calling prefixes.
- Personal-name formats and salutations, with illustrative formatted samples.
- Yes/no labels and POSIX extended response expressions, with native glibc match samples.
- Postal-address layouts and country/language identifiers.
- Locale metadata: title, maintainer/contact information, language/territory, audience/application, revision and date.

Character handling has a complete-profile picker (Unicode/glibc first, followed by locale profiles) and an editable test sample. The compiled preview shows character classes, simple upper/lowercase mappings, and ASCII transliteration. Character tables and sorting rules remain inherited as complete profiles; individual table/rule authoring is still a future extension. The sorting picker offers the installed ISO/IEC 14651 template first. Editing `LC_MESSAGES` changes yes/no handling, not application translation catalogs.

Postal-address presets are deduplicated across the full source catalog, with a multi-line mailing-label preview and Custom editing. `%N` adds a newline only after a nonempty field; `%t` conditionally adds a space. `%R` variants use supplied romanized sample fields when available. Samples are fictitious components, not address validation. Full previews also include the mailing label. Editing metadata materializes `LC_IDENTIFICATION` and preserves its category declarations; the metadata title is independent of the output locale name.

The **Paper size** row offers ISO A0–A10 and B0–B10, JIS B4/B5, US Letter, Legal, Tabloid, Ledger, Executive, and Custom. Choosing a name updates width and height as one undoable edit; reset on that row restores both inherited values. **Fax-safe** is a custom **210 × 279 mm** size: as narrow as A4 and no taller than Letter. Letter is nominally 215.9 × 279.4 mm, but glibc stores whole millimetres, so the fax-safe height is rounded down. The locale does not configure printer margins or guarantee compatibility with a particular fax/printer. [Paper-size reference](https://ftp.pwg.org/pub/pwg/candidates/cs-pwgmsn21-20230915-5101.1.pdf)

Telephone presets include the requested `+country(area)number` display (`+%c(%a)%l`), compact `+countryareanumber` (`+%c%a%l`), and spaced international formatting. `%c` is the country code, `%a` the area code without its domestic trunk prefix, and `%l` the local number. The parentheses variant is a display preference: ITU E.123 does not prescribe parentheses in an international number. Phone examples use illustrative components; these templates are not a numbering-plan validator and only affect applications that use the locale data. [ITU E.123](https://www.itu.int/rec/T-REC-E.123)

The category descriptions explain the underlying data:

- **Address formats:** postal-address layout, such as house-number/street order, postcode/city order, and line breaks; also country/language identifiers. They do not contain your personal address.
- **Character handling:** letter/digit/space/punctuation classification, case mappings and transliteration. Sorting is the separate `LC_COLLATE` category.
- **Metadata:** descriptive information about the locale source—title, language, territory, author/contact, revision and date. This is `LC_IDENTIFICATION`, not file metadata or device information.

These meanings and field names are documented in [locale(5)](https://man7.org/linux/man-pages/man5/locale.5.html).

Changing a parent **retains overrides**. Reset a field to resume following its parent. The display distinguishes explicit overrides from inherited values and shows the defining source for inherited fields.

Projects are versioned JSON documents containing the output name, each category's parent, typed overrides and source change fingerprints. They do not bundle their source dependencies. Keep the same source catalog available when reopening or exporting. The TUI reports changed sources on open; saving accepts the current source fingerprints. Fingerprints detect changes, not authenticity.

Unmodified categories export as `copy "source"`. Modified basic categories are resolved through their parent chain and emitted in full, preserving unedited fields and unknown directives. The exporter normalizes source syntax and does not promise byte-for-byte comment preservation. Advanced collation/character definitions remain compiler-managed. Inheritance is resolved at **compile time**; installed binary data does not automatically follow future parent updates.

## International conventions in your chosen language

Choose **Locale → International conventions…** to apply a coordinated set in one undoable edit. Start with `en_US`, `de_DE`, or another language/territory, then choose either the generic currency sign **¤** or retain the existing symbol. Translated month/day names, names and salutations, yes/no text, country identifiers/calling code, postal layout, sorting, and character profile are preserved. The same presets are offered individually before definitions harvested from locale files, with provenance labels and examples.

| Area | First international choices | Scope |
| --- | --- | --- |
| Date/time | ISO 8601 calendar `YYYY-MM-DD`, week and ordinal dates; 24-hour time | Combined local time uses `T`; GNU date can add the actual UTC offset. Never a hard-coded `Z` for local time. |
| Week | Monday; at least four days in week 1 | Preserves the inherited day-list base; first workday is not prescribed. |
| Numbers | SI decimal point **or comma**; space-separated groups of three | The combined action preserves an existing point/comma. Uses U+202F narrow no-break space; ungrouped and ASCII-space alternatives are offered. glibc cannot suppress grouping only for four-digit numbers. |
| Paper | ISO 216 A4 first, then other A/B sizes | Fax-safe remains a separately labelled custom size. |
| Measurement | SI/metric | Sets glibc's metric flag; applications choose units and must consult it. |
| Telephone | Compact `+%c%a%l`, then spaced ITU E.123 display | E.164 numbering components must be valid and at most 15 digits. No domestic trunk prefix; templates cannot validate a numbering plan. The parentheses layout remains a display preference. |
| Currency | Matching digit grouping; optional Unicode **¤** sign | Both convention sets apply the same U+202F separator and groups of three to money. Monetary decimal separators and the ISO currency code are preserved; choosing **¤** additionally changes the display symbol. ISO 4217 `XXX` (no currency involved) is a separate explicit choice. |
| Sorting | ISO/IEC 14651 common template | Uses the host's `iso14651_t1`; its table edition follows installed glibc data. |
| Characters | Unicode-derived glibc profile | Classification/simple case maps and neutral transliteration; not a claim of full Unicode or ISO certification. |

There is no single universal name order, postal-address layout, yes/no wording, currency, country, or language identifier to impose. Existing ISO country/language identifiers remain editable using source presets. “International standard” identifies particular formats/conventions, not certification of the entire locale. Applications using ICU or private settings may ignore glibc locales.

References: [ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html), [ISO 216](https://www.iso.org/standard/36631.html), [BIPM decimal and grouping rules](https://www.bipm.org/en/-/committees/ci/cipm/92-2003/resolution-2), [ITU E.123](https://www.itu.int/rec/T-REC-E.123), [ITU E.164](https://www.itu.int/rec/T-REC-E.164), [Unicode currency sign](https://unicode.org/Public/18.0.0/charts/nameslist/0080/), [ISO 4217](https://www.iso.org/iso-4217-currency-codes.html), [ISO/IEC 14651](https://committee.iso.org/standard/87359.html).

## Previews and compilation

Formatted examples are visible under the fields and refresh automatically when a value or parent changes. The sample is 27 October 2026, 17:04:05 UTC. The editor keeps one compiled preview per project state and batches preset-format rendering, so browsing a list does not recompile each candidate.

Date/time popup examples use the active locale's names and conventions. `date_fmt` uses GNU `date`, including extensions such as `%:z`; the other time formats use glibc `strftime`. Numeric and monetary popup candidates use illustrative samples; once applied, compiled glibc examples replace them. Telephone templates are read back from the compiled locale, while their presentation samples remain illustrative. Unrecognized format conversions retain the formatting engine's literal behavior. Invalid/incomplete values or compiler failures are displayed explicitly, without stale previews.

Press F5 or `p` for additional sample dates (including leap day and a year boundary), positive/negative/zero numbers and currency amounts, and a customizable sorting sample. A separate process uses the compiled locale through `LOCPATH` and `LC_ALL`:

- Date/time: glibc `strftime`.
- Numbers: glibc `snprintf` with locale grouping.
- Currency: glibc `strfmon`.
- Sorting: glibc `strcoll`, with stable ordering for equivalent strings.
- Yes/no: POSIX `regcomp`/`regexec` in the compiled locale; invalid expressions and overlapping matches are reported.
- Character handling: glibc wide-character classes and simple case conversion, plus `iconv` ASCII transliteration. These are not full Unicode normalization or multi-character case folding.

The preview also queries the compiled first-weekday/workday, paper and measurement settings using `locale -k`.

The child process avoids changing the editor's locale and prevents stale libc caches when rebuilding the same locale name. Compiler errors and warnings are shown; compilation is not forced past warnings. Linux workers use `posix_spawn` and direct `waitpid` reaping, with monotonic deadlines and private output files; they do not depend on a Foundation or GUI run loop. Processes have bounded execution times. Full locale compilation allows up to two minutes for slower machines such as Raspberry Pi; preview workers retain shorter limits. All calls use argument arrays, never shell interpolation.

`b` writes individual compiled files to a new subdirectory. Existing compiled destinations are not overwritten, and this build-only action does not change session/system settings. To test a compiled locale in an application:

```sh
LOCPATH="$PWD/locale-output" LC_ALL=en_GB.UTF-8@personal date '+%x %X'
```

Applications using ICU or their own formatting preferences may not use glibc's custom data. This first backend targets glibc Linux, not musl.

## Install and select

Press **`a`**, or choose **File → Export / compile / activate…** for the output workflow. Choose source export, directory compilation, installation only, or installation and activation. **Locale → Install and select…** also opens installation directly. Installation performs compilation and includes exported source plus the editable project; no separate export/build step is required. The default scope is **Current user**; **System-wide** is also available. Each scope offers either Install and select or Install only. The application compiles and verifies a prepared package, shows destination/selection files for review, and asks for final confirmation. System-wide installation requests administrator authentication through polkit. The GTK GUI uses the desktop authentication agent; the TUI allows the desktop or text agent. Development installations can fall back to `sudo` if pkexec is unavailable. Password input is not handled or logged by the editor.

| Scope | Installed locale | Selection |
| --- | --- | --- |
| Current user | `$XDG_DATA_HOME/linux-locale-editor/locales/NAME`, normally `~/.local/share/linux-locale-editor/locales/NAME` | An activation script, an `environment.d` file, and managed blocks in supported shell startup files |
| System-wide | `/usr/lib/locale/NAME` | `/etc/locale.conf` and any existing legacy `/etc/default/locale`, with symlink targets deduplicated |

Per-user selection writes `LANG` and `LOCPATH` and clears category overrides. Bash, zsh, sh and dash startup files are supported; zsh's absolute `ZDOTDIR` is honored. Original content outside the managed blocks is retained. Other shells can source the generated POSIX activation script from an appropriate wrapper or use the generated user-service environment configuration. `environment.d` is applied by a new/reloaded systemd user manager; new interactive/login shells read their startup files. System selection writes `LANG` and clears system category overrides; existing user overrides can still take precedence. New logins read the new defaults; services may need restarting or a reboot.

An application cannot change the environment of its parent shell or already-running programs. The completion screen supplies `. '/path/to/activate.sh'` for applying a per-user selection to an existing POSIX-compatible shell. Per-user `LOCPATH` disables use of glibc's locale archive: programs that explicitly select other archive-only locales may need those locales generated as separate files. A system installation avoids that per-user search-path limitation. See [locale(7)](https://man7.org/linux/man-pages/man7/locale.7.html) and [environment.d](https://www.freedesktop.org/software/systemd/man/latest/environment.d.html).

Installations contain the compiled categories, editable project, exported source, and an ownership receipt. Existing unrelated locales and archive-name collisions are rejected. Updating an app-owned installation requires explicit replacement. The previous locale and original selection files are backed up under the app's `backups/NAME/…` directory; `selection-backups.json` identifies each original and whether a file previously existed. Selection-write failures roll back completed writes and the installed locale. Backup records can also be used to restore a previous successful selection manually; start a new session afterward.

The privileged helper accepts only validated package names and a fixed set of regular files, rejects symlinks in package paths, and verifies glibc lookup before selecting a default. On Linux it checks the mapped category files by device/inode identity: `setlocale` can echo a requested name even after falling back to another locale. It does not modify the system archive. Installer tests use temporary user/system layouts; they do not change the build machine's actual defaults.

For scripted per-user installation:

```sh
./bin/locale-editor install --project personal.json --scope user --select
# To update an installation previously made by this app:
./bin/locale-editor install --project personal.json --scope user --select --replace
```

Omit `--select` for installation only. For system-wide installation, the interactive frontends perform compilation before privilege elevation; an administrator can also invoke the CLI with `--scope system`.

## macOS development

The core, TUI, project persistence and source export work on macOS. Synthetic demonstration sources are included so the interface can be used without a Linux source catalog:

```sh
swift run locale-editor --sources Examples/locales --base demo_en
```

These samples are not official locales and have deliberately minimal character/sorting definitions. Use real distribution sources for deployment. Compilation and authoritative previews require Linux; Foundation/ICU output is deliberately not presented as a glibc preview.

For container-based Linux development on macOS, use Apple’s `container` tooling:

```sh
container build --cpus 4 --memory 6G -t linux-locale-editor-test:local .
container run --rm --cpus 4 --memory 6G linux-locale-editor-test:local
mkdir -p projects
container run --rm -i -t --cpus 4 --memory 6G -v "$PWD/projects:/projects" linux-locale-editor-test:local \
  .build/debug/locale-editor --base en_GB
```

Save to `/projects/my-locale.json` inside that container to retain a project. Other container-local output is removed when it exits.

## Noninteractive commands

```sh
./bin/locale-editor list
./bin/locale-editor new --base en_GB --name en_GB.UTF-8@personal --output personal.json
./bin/locale-editor edit --project personal.json
./bin/locale-editor export --project personal.json --output personal.src
./bin/locale-editor preview --project personal.json
./bin/locale-editor compile --project personal.json --output locale-output
```

`preview` prints JSON. `--words-file words.json` supplies an array of strings for sorting. `new` and `export` require `--force` to replace an existing file. Use `--sources` with any command to select additional catalogs.

## Shared core and native Linux frontends

| Target | Responsibility |
| --- | --- |
| `LocaleCore` | Source parsing/catalog, inheritance, field schema, typed project model, undo/redo, persistence, source export |
| `LocaleRuntime` | Process execution, glibc compilation and preview reports |
| `LocaleEditorTUI` | Terminal rendering, navigation, dialogs and CLI entry point |
| `CLocaleBridge` | Small POSIX bridge for terminal setup/widths and C variadic formatting calls unavailable directly from Swift |
| `LocaleEditorGUI` | Swift GTK controller, asynchronous preview jobs, native dialogs and GUI editing flow (GUI build only) |
| `CGtkBridge` / `CGtk` | GTK widget/signal bridge and system-library import (GUI build only) |

`EditorSession` is the frontend-independent mutation boundary. `FieldSchema` supplies labels, help, value kinds and validation. `LocaleCatalog.inheritedValue` resolves parent values. `LocalePresetIndex`, `InternationalConventions`, `SectionProfiles`, `CurrencySymbols` and `FieldExamples` provide the reusable choice catalogs and illustrative samples. `CompiledPreview` owns a compiled snapshot and provides batched engine-rendered examples. Frontends can consume these interfaces without sharing terminal focus/layout code. The GTK controller performs compilation, preset indexing and installation on a serial worker queue, then delivers results to GTK through its main context. It uses isolated preview processes rather than changing the GUI process locale. Immutable catalog and compiled-preview handles are Sendable.

`PostalAddresses` and `PersonalNames` render reusable illustrative samples. `BehaviorRequest`/`BehaviorReport` expose native regex and character behavior without terminal dependencies. `PreparedLocaleInstall`, `LocaleInstaller`, and `LocaleSelection` keep installation, activation plans, collision protection and rollback independent of the TUI. `AdministratorInstall` runs the prepared-package helper through polkit and distinguishes cancellation, denial and successful installation. Credentials remain with the authentication agent.

The project document and exporter are separate: future collation editors can introduce additional structured data and export rules without making the TUI the source of truth. Unsupported project versions and override fields are rejected rather than silently discarded.

### Building both editions

On Debian-family systems, the GUI build requires GTK 3 development headers; package generation needs dpkg development tools and desktop-file-utils:

```sh
sudo apt install libgtk-3-dev dpkg-dev desktop-file-utils
bash Scripts/build-debs.sh
```

The script builds separate release graphs under `.build/package-tui` and `.build/package-gui`, checks the absence of graphical dependencies in the terminal build, embeds the Swift runtime, computes runtime dependencies, and writes both `.deb` files and a checksum file under `dist/`. The packages declare `Provides`, `Conflicts` and `Replaces` relationships. No package-install hooks change locale configuration.

`LOCALE_EDITOR_BUILD_JOBS=2` limits parallelism for smaller build machines. Build and test arm64 packages on an arm64 Linux host. `Scripts/prepare-swift-arm64.sh` optionally installs the official signed Swift 6.4.1 toolchain into the checkout’s `.build` directory; it does not modify system packages. Its generated `.build/swift-arm64-env.sh` supplies the compiler path. Use an execution-enabled build directory.

The same builds are also available as executables in `bin/tui/` and `bin/gui/`. To build only the GTK development executable:

```sh
LOCALE_EDITOR_GUI=1 swift build --scratch-path .build/gui
.build/gui/debug/locale-editor --base en_US
.build/gui/debug/locale-editor --tui --base en_US
```

Without `LOCALE_EDITOR_GUI=1`, the build graph contains no GTK targets or dependencies. `Scripts/build-release.sh` continues to build the standalone terminal release in `bin/locale-editor` by default. The macOS source-editing demo remains a development aid; the GTK GUI and locale runtime target Linux.

For an unprivileged Debian build host with GTK runtimes already installed, `python3 Scripts/prepare-gtk-sdk.py` can unpack the missing development packages into `.build/gtk-sdk/`. Source `.build/gtk-sdk/env.sh` before building. This optional build aid does not install or upgrade system packages, and the private SDK is not shipped in the `.deb` files. Normal distribution development packages are preferred for reproducible release builds.

The installed helper and polkit action use `/usr/bin/locale-editor --install-system`. The action matches the executable path and first argument. The helper independently validates its arguments and package contents; invocation names are not authorization checks. Only the helper runs with administrative privileges. The authentication cancellation path preserves the editor and project.

An embedded KDE configuration module would require a Qt/QML-facing KCM plug-in in addition to the shared backend. That target is not included in these packages.

References: [GTK application integration](https://docs.gtk.org/gtk3/class.Application.html), [KDE KCM development](https://develop.kde.org/docs/features/configuration/kcm/), [polkit authentication and actions](https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html), [pkexec helper execution](https://www.freedesktop.org/software/polkit/docs/latest/pkexec.1.html).

## Tests

```sh
swift test
python3 Scripts/test-tui.py .build/debug/locale-editor
python3 Scripts/test-mouse.py .build/debug/locale-editor
python3 Scripts/test-menus.py .build/debug/locale-editor
python3 Scripts/test-files-and-formats.py .build/debug/locale-editor
python3 Scripts/test-postal-install.py .build/debug/locale-editor
python3 Scripts/test-international.py .build/debug/locale-editor
```

The core tests cover inheritance chains/cycles, syntax and Unicode escaping, continued and commented strings, preset deduplication/provenance, the currency catalog, transactional edits, persistence and recursive formats. The keyboard PTY test exercises colors, automatic examples, preset/Custom selection, Unicode search, standard navigation, saved legacy preferences and terminal restoration. Mouse tests cover protocol decoding, hit-region boundaries, modal isolation, clicks, wheel scrolling, Unicode cursor placement, fragmented reports, resize handling and reporting cleanup. Linux integration tests compile a locale combining British date conventions, Austrian numeric/currency data and Swedish collation, then verify actual output, batched examples, GNU date extensions and a rebuild under the same name.

Menu unit and PTY tests cover mnemonics, disabled actions, wrapping, separators, resize/clipping, mouse hit targets, outside-click dismissal, real save/export/open actions, cursor options and unsaved-change protection. The shared PTY harness is in `Scripts/tui_harness.py`.

File-browser tests cover navigation, hidden files, Unicode/spaced paths, symlinks, invalid destinations, overwrite cancellation, directory creation and resize behavior. Paper/telephone tests verify atomic paired edits, named-size matching, saved project/source values and actual `localedef` output.

Postal and metadata tests cover conditional formatting, romanized sample fields, metadata/category preservation and legacy numeric ISBN fields. Installer tests cover package symlink rejection, foreign-locale protection, managed profile blocks, actual shell activation, replacement/backups and rollback in isolated user/system roots. The postal/install PTY test exercises editing and a temporary per-user install-only operation; it never modifies real shell profiles or system defaults.

Run `bash Scripts/check-linux.sh` on Linux, or the Docker commands above. The glibc test explicitly skips on macOS. CI runs the Linux suite and PTY test using Swift 6.0.

For restricted macOS build environments that block SwiftPM's nested build sandbox or global module cache:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox
```

## Format references

- [Locale source format](https://man7.org/linux/man-pages/man5/locale.5.html)
- [localedef compiler](https://man7.org/linux/man-pages/man1/localedef.1.html)
- [strftime formats](https://man7.org/linux/man-pages/man3/strftime.3.html)
- [strfmon currency formatting](https://man7.org/linux/man-pages/man3/strfmon.3.html)

GTK integration tests use a private Xvfb/D-Bus session and native AT-SPI accessibility actions. They cover presets, custom fields, compiled examples, undo/redo, native file dialogs, source export, compilation, temporary per-user installation, system-scope cancellation, and unsaved-change protection. They require `xvfb`, `xfwm4`, `python3-gi`, the Atspi typelib, `xdotool`, and ImageMagick for captures. Tests never install a real system locale or alter the host's default locale.

```sh
bash Scripts/check-gui.sh .build/gui/debug/locale-editor .build/gui-captures
python3 Scripts/test-debs.py dist/locale-editor-tui_0.2.0-2_amd64.deb dist/locale-editor-gui_0.2.0-2_amd64.deb
```

Package checks extract into temporary directories and simulate apt operations. They verify file ownership/modes, runtime dependency isolation, desktop/polkit metadata, no-display CLI workers, invocation aliases, mutual exclusion and switching in both directions.

`Scripts/test-startup.py` repeatedly starts the terminal editor with a saved project to guard against exited-worker wait stalls. Process-runner tests also exercise rapid exits, concurrent workers, output isolation, environment validation, and timeout cleanup of subprocess groups.
