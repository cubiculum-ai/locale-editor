import Foundation
import LocaleRuntime

enum EditorCommand: Equatable {
    case selectSection, inherit, rename, open, save, saveAs, viewSource, export, compile, quit
    case choosePreset, customValue, reset, undo, redo, preview, sortingWords, cursorOptions, help, license, install
    case international, finish
}

struct MenuLabel {
    let text: String
    let mnemonic: String?
    let mnemonicColumn: Int?
    init(_ marked: String) {
        let characters = Array(marked)
        if let index = characters.firstIndex(of: "&"), index + 1 < characters.count {
            text = String(characters[..<index]) + String(characters[(index + 1)...])
            mnemonic = String(characters[index + 1]).lowercased()
            mnemonicColumn = Screen.displayWidth(String(characters[..<index]))
        } else { text = marked; mnemonic = nil; mnemonicColumn = nil }
    }
}

struct MenuItem {
    let label: MenuLabel
    let command: EditorCommand?
    let shortcut: String
    let enabled: Bool
    let unavailableReason: String
    var isSeparator: Bool { command == nil }
    init(_ label: String, _ command: EditorCommand, shortcut: String = "", enabled: Bool = true, reason: String = "") {
        self.label = MenuLabel(label); self.command = command; self.shortcut = shortcut
        self.enabled = enabled; unavailableReason = reason
    }
    private init() { label = MenuLabel(""); command = nil; shortcut = ""; enabled = false; unavailableReason = "" }
    static var separator: Self { Self() }
}

struct AppMenu {
    let label: MenuLabel
    let items: [MenuItem]
    init(_ label: String, _ items: [MenuItem]) { self.label = MenuLabel(label); self.items = items }
}

struct MenuAvailability {
    var fieldSelected: Bool
    var canUndo: Bool
    var canRedo: Bool
    var canPreview: Bool
    var canCompile: Bool
}

enum EditorMenus {
    static func make(_ state: MenuAvailability) -> [AppMenu] {
        [
            AppMenu("&Locale", [
                MenuItem("&Select section…", .selectSection),
                MenuItem("&Inherit section…", .inherit, shortcut: "F6"),
                MenuItem("&Rename locale…", .rename, shortcut: "n"),
                MenuItem("International &conventions…", .international),
                .separator,
                MenuItem("Formatted &preview", .preview, shortcut: "F5", enabled: state.canPreview, reason: "No compiled preview is available."),
                MenuItem("Sorting &words…", .sortingWords, shortcut: "w"),
                .separator,
                MenuItem("Ins&tall and select…", .install, enabled: state.canCompile, reason: "Installation requires Linux/glibc."),
            ]),
            AppMenu("&File", [
                MenuItem("&Open project…", .open, shortcut: "o"),
                MenuItem("&Save project…", .save, shortcut: "F2"),
                MenuItem("Save project &as…", .saveAs),
                .separator,
                MenuItem("&View generated source", .viewSource, shortcut: "F3"),
                MenuItem("&Export locale source…", .export, shortcut: "e"),
                MenuItem("&Compile locale…", .compile, shortcut: "b", enabled: state.canCompile, reason: "Compilation requires Linux/glibc."),
                MenuItem("Export / compile / ac&tivate…", .finish, shortcut: "a"),
                .separator,
                MenuItem("&Quit", .quit, shortcut: "F10"),
            ]),
            AppMenu("&Edit", [
                MenuItem("Choose &preset…", .choosePreset, shortcut: "F7", enabled: state.fieldSelected, reason: "Select an editable field first."),
                MenuItem("&Custom value…", .customValue, shortcut: "F4", enabled: state.fieldSelected, reason: "Select an editable field first."),
                MenuItem("&Reset to inherited", .reset, shortcut: "F8", enabled: state.fieldSelected, reason: "Select an editable field first."),
                .separator,
                MenuItem("&Undo", .undo, shortcut: "u", enabled: state.canUndo, reason: "Nothing to undo."),
                MenuItem("Re&do", .redo, shortcut: "y", enabled: state.canRedo, reason: "Nothing to redo."),
            ]),
            AppMenu("&Options", [MenuItem("&Cursor behavior…", .cursorOptions)]),
            AppMenu("&Help", [
                MenuItem("Keyboard and mouse &help", .help, shortcut: "F1"),
                MenuItem("Unicode data &license", .license),
            ]),
        ]
    }
}

/// Menu navigation is separate from command execution and terminal IO, so disabled actions,
/// separators and wrapping are exercised without starting an interactive terminal.
struct MenuSelection {
    let menus: [AppMenu]
    private(set) var heading: Int
    private(set) var item: Int?
    var offset = 0
    var current: AppMenu { menus[heading] }
    var command: EditorCommand? { item.flatMap { current.items[$0].command } }

    init(menus: [AppMenu], heading: Int) {
        precondition(!menus.isEmpty)
        self.menus = menus
        self.heading = min(max(0, heading), menus.count - 1)
        item = menus[self.heading].items.firstIndex { $0.enabled }
    }
    mutating func selectHeading(_ index: Int) {
        guard menus.indices.contains(index) else { return }
        heading = index; item = current.items.firstIndex { $0.enabled }; offset = 0
    }
    mutating func moveHeading(_ delta: Int) {
        selectHeading((heading + delta % menus.count + menus.count) % menus.count)
    }
    mutating func moveItem(_ delta: Int) {
        let available = current.items.indices.filter { current.items[$0].enabled }
        guard !available.isEmpty else { item = nil; return }
        let position = item.flatMap { available.firstIndex(of: $0) } ?? 0
        item = available[(position + delta % available.count + available.count) % available.count]
    }
    mutating func edge(first: Bool) {
        let available = current.items.indices.filter { current.items[$0].enabled }
        item = first ? available.first : available.last
    }
    func heading(mnemonic: String) -> Int? { menus.firstIndex { $0.label.mnemonic == mnemonic.lowercased() } }
    func item(mnemonic: String) -> Int? { current.items.firstIndex { $0.label.mnemonic == mnemonic.lowercased() } }
    mutating func selectItem(_ index: Int) {
        if current.items.indices.contains(index), current.items[index].enabled { item = index }
    }
}

extension Screen {
    @discardableResult
    mutating func menuBar(_ menus: [AppMenu], active: Int? = nil) -> [CellRect] {
        write("", x: 0, y: 0, ink: .menu)
        var x = 0, bounds: [CellRect] = []
        for (index, menu) in menus.enumerated() {
            let count = Self.displayWidth(menu.label.text) + 2
            let rect = CellRect(x: x, y: 0, width: count, height: 1)
            write(" " + menu.label.text + " ", x: x, y: 0, width: count, ink: active == index ? .bright : .menu)
            if let column = menu.label.mnemonicColumn, let mnemonic = menu.label.mnemonic {
                write(mnemonic.uppercased(), x: x + 1 + column, y: 0, width: 1, ink: active == index ? .menuHotkeyActive : .menuHotkey)
            }
            clickTarget(.menuHeading(index), x: x, y: 0, width: count)
            bounds.append(rect); x += count + 1
        }
        return bounds
    }

    mutating func dropdown(_ selection: inout MenuSelection) -> CellRect {
        clearTargets()
        let headings = menuBar(selection.menus, active: selection.heading)
        let entries = selection.current.items
        let longest = entries.map { Self.displayWidth($0.label.text) + Self.displayWidth($0.shortcut) + 7 }.max() ?? 20
        let w = min(width, max(26, longest)), x = min(headings[selection.heading].x, width - w)
        let visible = max(1, min(entries.count, height - 5)), y = 1
        selection.offset = min(max(0, selection.offset), max(0, entries.count - visible))
        if let item = selection.item {
            if item < selection.offset { selection.offset = item }
            if item >= selection.offset + visible { selection.offset = item - visible + 1 }
        }
        let bounds = CellRect(x: x, y: y, width: w, height: visible + 2)
        box(x: x, y: y, width: w, height: visible + 2)
        scrollTarget(.menu, x: x, y: y, width: w, height: visible + 2)
        for index in selection.offset..<min(entries.count, selection.offset + visible) {
            let entry = entries[index], row = y + 1 + index - selection.offset
            if entry.isSeparator {
                write("├" + String(repeating: "─", count: w - 2) + "┤", x: x, y: row, width: w, ink: .border)
                continue
            }
            let active = selection.item == index
            let ink: Ink = !entry.enabled ? .disabled : active ? .selected : .panel
            write(" " + entry.label.text, x: x + 1, y: row, width: w - 2, ink: ink)
            if !entry.shortcut.isEmpty { write(entry.shortcut, x: x + w - 2 - Self.displayWidth(entry.shortcut), y: row, width: Self.displayWidth(entry.shortcut), ink: ink) }
            if entry.enabled, let column = entry.label.mnemonicColumn {
                let characters = Array(entry.label.text)
                // Menu labels are ASCII with a possible trailing ellipsis; mnemonic columns are ASCII.
                write(String(characters[column]), x: x + 2 + column, y: row, width: 1, ink: active ? .menuHotkey : .menuHotkeyActive)
            }
            clickTarget(.menuItem(index), x: x + 1, y: row, width: w - 2)
        }
        functionBar(["Help", "", "", "", "", "", "", "", "Close", "Cancel"])
        return bounds
    }
}

struct MenuResult { let command: EditorCommand?; let heading: Int }

extension Terminal {
    func menu(_ menus: [AppMenu], initial: Int) -> MenuResult {
        var selection = MenuSelection(menus: menus, heading: initial)
        let hint = "←/→ menus · ↑/↓ commands · Enter / highlighted letter · Esc closes"
        var redraw = true, oldSize = "", status = hint
        var bounds = CellRect(x: 0, y: 0, width: 0, height: 0)
        while true {
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            if redraw || size != oldSize {
                var screen = backdrop()
                bounds = screen.dropdown(&selection)
                screen.write(status, x: 0, y: screen.height - 2, ink: .status)
                present(screen, remember: false); oldSize = size
            }
            let key = key(); redraw = key != .tick
            switch key {
            case .escape, .quit, .function(9), .function(10): return MenuResult(command: nil, heading: selection.heading)
            case .left, .backTab: selection.moveHeading(-1); status = hint
            case .right, .tab: selection.moveHeading(1); status = hint
            case .up: selection.moveItem(-1); status = hint
            case .down: selection.moveItem(1); status = hint
            case .home, .pageUp: selection.edge(first: true); status = hint
            case .end, .pageDown: selection.edge(first: false); status = hint
            case .enter: if let command = selection.command { return MenuResult(command: command, heading: selection.heading) }
            case .alt(let letter):
                if let index = selection.heading(mnemonic: letter) { selection.selectHeading(index); status = hint }
            case .text(let letter):
                if let index = selection.item(mnemonic: letter) {
                    let item = selection.current.items[index]
                    if item.enabled { return MenuResult(command: item.command, heading: selection.heading) }
                    status = item.unavailableReason
                } else if let index = selection.heading(mnemonic: letter) { selection.selectHeading(index); status = hint }
            case .function(let number):
                if let item = menus.flatMap(\.items).first(where: { $0.enabled && $0.shortcut == "F\(number)" }) {
                    return MenuResult(command: item.command, heading: selection.heading)
                }
            case .mouse(let event):
                if case .wheel(let delta) = event.kind, scroll(at: event) == .menu { selection.moveItem(delta); status = hint }
                else if event.isPrimaryPress {
                    switch click(at: event) {
                    case .menuHeading(let index): selection.selectHeading(index); status = hint
                    case .menuItem(let index):
                        let item = selection.current.items[index]
                        if item.enabled { return MenuResult(command: item.command, heading: selection.heading) }
                        status = item.unavailableReason
                    default:
                        if !bounds.contains(x: event.x, y: event.y) { return MenuResult(command: nil, heading: selection.heading) }
                    }
                }
            default: break
            }
        }
    }
}
