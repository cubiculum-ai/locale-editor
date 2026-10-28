import Foundation
import LocaleCore
import LocaleRuntime

private enum FileFocus: Int { case path, list, name }

extension Terminal {
    func confirmReplacement(_ url: URL) -> Bool {
        var replaceSelected = false, offset = 0, redraw = true, oldSize = ""
        while true {
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            var screen = backdrop()
            let w = min(screen.width - 4, 110)
            let lines = Screen.wrapped("File: \(url.lastPathComponent)\nDirectory: \(url.deletingLastPathComponent().path)", width: w - 6)
            let visible = max(1, min(lines.count, screen.height - 9))
            let h = visible + 6, x = max(0, (screen.width - w) / 2), y = max(1, (screen.height - h) / 2)
            offset = min(max(0, offset), max(0, lines.count - visible))
            if redraw || size != oldSize {
                screen.box(x: x, y: y, width: w, height: h, title: "Replace existing file?", dialog: true)
                for (row, line) in lines.dropFirst(offset).prefix(visible).enumerated() { screen.write(line, x: x + 3, y: y + 2 + row, width: w - 6, ink: .dialog) }
                screen.write("Tab / arrows choose · Enter confirms · Esc cancels · PgUp/PgDn scroll path", x: x + 3, y: y + h - 3, width: w - 6, ink: .dialog)
                screen.button("Replace", x: x + 4, y: y + h - 2, action: .accept)
                screen.button("Cancel", x: x + 20, y: y + h - 2, action: .cancel)
                screen.write(">", x: x + (replaceSelected ? 3 : 19), y: y + h - 2, width: 1, ink: .dialog)
                screen.scrollTarget(.page, x: x, y: y, width: w, height: h)
                screen.functionBar(["", "Replace", "", "", "", "", "", "", "", "Cancel"])
                present(screen, remember: false); oldSize = size
            }
            let key = key(); redraw = key != .tick
            switch key {
            case .escape, .quit, .function(10), .text("n"): return false
            case .function(2), .text("y"): return true
            case .enter: return replaceSelected
            case .tab, .backTab, .left, .right: replaceSelected.toggle()
            case .pageDown: offset += visible
            case .pageUp: offset -= visible
            case .mouse(let event):
                if case .wheel(let direction) = event.kind, scroll(at: event) == .page { offset += direction * 3 }
                else if click(at: event) == .accept { return true }
                else if click(at: event) == .cancel { return false }
            default: break
            }
        }
    }

    func fileDialog(mode: FileDialogMode, initial: URL) throws -> URL? {
        var isDirectory: ObjCBool = false
        let initialIsDirectory = FileManager.default.fileExists(atPath: initial.path, isDirectory: &isDirectory) && isDirectory.boolValue
        var browser = try FileBrowser(directory: initialIsDirectory ? initial : initial.deletingLastPathComponent())
        var path = FileTextBuffer(browser.directory.path)
        var name = FileTextBuffer(initialIsDirectory ? "" : initial.lastPathComponent)
        var selected = browser.entries.firstIndex { $0.name == name.text } ?? 0
        var offset = 0, focus = FileFocus.name, redraw = true, oldSize = ""
        var status = "All files shown · Tab: directory / list / filename · Enter: open directory or accept file"
        var pathLeft = 0, nameLeft = 0
        var quickSearch = "", lastSearch = Date.distantPast

        func directory(_ url: URL) throws {
            try browser.navigate(to: url)
            path.replace(browser.directory.path)
            selected = 0; offset = 0; quickSearch = ""
            if mode == .open { name.replace("") }
            status = "Directory: " + browser.directory.path
        }
        func chooseFile(_ entry: BrowserEntry) { name.replace(entry.name) }
        func acceptName() throws -> URL? {
            let url = try browser.destination(name.text, mode: mode)
            if mode == .compile { return url }
            var directoryFlag: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directoryFlag), directoryFlag.boolValue {
                try directory(url); name.replace(""); focus = .list
                return nil
            }
            return url
        }
        func activate() throws -> URL? {
            if focus == .path { try directory(browser.resolve(path.text)); focus = .list; return nil }
            if focus == .list, browser.entries.indices.contains(selected) {
                let entry = browser.entries[selected]
                if entry.directory { try directory(entry.url); return nil }
                chooseFile(entry)
            }
            return try acceptName()
        }
        func acceptButton() throws -> URL? {
            if mode == .open { return try activate() }
            if focus == .path && path.text != browser.directory.path { try directory(browser.resolve(path.text)) }
            // Save/Export apply the filename in the displayed directory even if the list
            // happens to highlight '..' immediately after entering a folder.
            return try acceptName()
        }

        while true {
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            let capacity = max(1, min(max(8, TerminalGeometry.rows) - 2, 34) - 12)
            selected = min(max(0, selected), max(0, browser.entries.count - 1))
            offset = min(max(0, offset), max(0, browser.entries.count - capacity))
            if selected < offset { offset = selected }
            if selected >= offset + capacity { offset = selected - capacity + 1 }
            if redraw || size != oldSize {
                var screen = backdrop()
                let w = min(screen.width - 2, 130), h = min(screen.height - 2, 34)
                let x = max(0, (screen.width - w) / 2), y = max(1, (screen.height - h) / 2)
                screen.box(x: x, y: y, width: w, height: h, title: mode.title)
                screen.write("Directory:", x: x + 2, y: y + 2, width: 10, ink: .bright)
                pathLeft = x + 13; nameLeft = x + 9
                let pathView = path.visible(width: w - 15)
                screen.write(pathView.text, x: pathLeft, y: y + 2, width: w - 15, ink: focus == .path ? .input : .panel)
                screen.clickTarget(.filePath, x: pathLeft, y: y + 2, width: w - 15)
                screen.button("Up", x: x + 2, y: y + 3, action: .parentDirectory)
                screen.button("Home", x: x + 10, y: y + 3, action: .homeDirectory)
                screen.button(browser.showHidden ? "Hidden: on" : "Hidden: off", x: x + 20, y: y + 3, action: .toggleHidden)
                screen.write("Name", x: x + 2, y: y + 5, width: w - 18, ink: .accent)
                screen.write("Bytes / type", x: x + w - 16, y: y + 5, width: 14, ink: .accent)
                screen.scrollTarget(.files, x: x + 1, y: y + 6, width: w - 2, height: capacity)
                for index in offset..<min(browser.entries.count, offset + capacity) {
                    let entry = browser.entries[index], row = y + 6 + index - offset
                    let ink: Ink = index == selected ? (focus == .list ? .selected : .selectedInactive) : .panel
                    screen.write(entry.displayName, x: x + 2, y: row, width: w - 18, ink: ink)
                    screen.write(entry.directory ? "<DIR>" : entry.size.map(String.init) ?? "?", x: x + w - 16, y: row, width: 14, ink: ink)
                    screen.clickTarget(.fileEntry(index), x: x + 2, y: row, width: w - 4)
                }
                screen.write("Name:", x: x + 2, y: y + h - 5, width: 6, ink: .bright)
                let nameView = name.visible(width: w - 11)
                screen.write(nameView.text, x: nameLeft, y: y + h - 5, width: w - 11, ink: focus == .name ? .input : .panel)
                screen.clickTarget(.fileName, x: nameLeft, y: y + h - 5, width: w - 11)
                screen.write("Tab switches focus · Alt+P path / Alt+L list / Alt+N name · Ctrl-U clears", x: x + 2, y: y + h - 4, width: w - 4)
                screen.write(status, x: x + 2, y: y + h - 3, width: w - 4, ink: .accent)
                screen.button(mode.action, x: x + 2, y: y + h - 2, action: .accept)
                screen.button("Cancel", x: x + 15, y: y + h - 2, action: .cancel)
                screen.functionBar(["", mode.action, "", "", "Refresh", "Up", "MkDir", "Hidden", "", "Cancel"])
                let cursor: (Int, Int)? = focus == .path ? (pathLeft + pathView.cursorColumn, y + 2) : focus == .name ? (nameLeft + nameView.cursorColumn, y + h - 5) : nil
                present(screen, cursor: cursor, remember: false)
                oldSize = size
            }
            let key = key(); redraw = key != .tick
            do {
                switch key {
                case .escape, .quit, .function(10): return nil
                case .tab: focus = FileFocus(rawValue: (focus.rawValue + 1) % 3)!
                case .backTab: focus = FileFocus(rawValue: (focus.rawValue + 2) % 3)!
                case .alt("p"), .location: focus = .path
                case .alt("l"): focus = .list
                case .alt("n"): focus = .name
                case .alt("h"): try directory(FileManager.default.homeDirectoryForCurrentUser)
                case .enter: if let result = try activate() { return result }
                case .function(2): if let result = try acceptButton() { return result }
                case .function(5): try browser.navigate(to: browser.directory)
                case .function(6): try directory(browser.directory.deletingLastPathComponent())
                case .function(8): try browser.toggleHidden(); selected = 0; offset = 0
                case .function(7):
                    if let folder = prompt("New directory", help: "A single directory name inside the displayed directory."), !folder.isEmpty {
                        guard folder != ".", folder != "..", !folder.contains("/"), !folder.utf8.contains(0) else { throw LocaleEditorError("Enter a single directory name.") }
                        let target = browser.directory.appendingPathComponent(folder)
                        guard !FileBrowser.existsIncludingSymlink(target) else { throw LocaleEditorError("That name already exists.") }
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                        try directory(target)
                    }
                case .up, .down:
                    focus = .list
                    selected = min(max(0, browser.entries.count - 1), max(0, selected + (key == .up ? -1 : 1)))
                    if browser.entries.indices.contains(selected), !browser.entries[selected].directory { chooseFile(browser.entries[selected]) }
                case .pageUp, .pageDown:
                    focus = .list
                    selected = min(max(0, browser.entries.count - 1), max(0, selected + (key == .pageUp ? -capacity : capacity)))
                    if browser.entries.indices.contains(selected), !browser.entries[selected].directory { chooseFile(browser.entries[selected]) }
                case .home where focus == .list: selected = 0
                case .end where focus == .list: selected = max(0, browser.entries.count - 1)
                case .left where focus == .list: try directory(browser.directory.deletingLastPathComponent())
                case .backspace where focus == .list: try directory(browser.directory.deletingLastPathComponent())
                case .right where focus == .list:
                    if browser.entries.indices.contains(selected), browser.entries[selected].directory { try directory(browser.entries[selected].url) }
                case .mouse(let event):
                    if case .wheel(let direction) = event.kind, scroll(at: event) == .files {
                        focus = .list
                        offset = min(max(0, browser.entries.count - capacity), max(0, offset + direction * 3))
                        selected = min(max(0, browser.entries.count - 1), min(offset + capacity - 1, max(offset, selected)))
                    } else {
                        switch click(at: event) {
                        case .fileEntry(let index) where browser.entries.indices.contains(index):
                            selected = index
                            if browser.entries[index].directory { try directory(browser.entries[index].url); focus = .list }
                            else { chooseFile(browser.entries[index]); focus = .name }
                        case .filePath: focus = .path; path.click(column: event.x - pathLeft)
                        case .fileName: focus = .name; name.click(column: event.x - nameLeft)
                        case .parentDirectory: try directory(browser.directory.deletingLastPathComponent())
                        case .homeDirectory: try directory(FileManager.default.homeDirectoryForCurrentUser)
                        case .toggleHidden: try browser.toggleHidden(); selected = 0; offset = 0
                        case .accept: if let result = try acceptButton() { return result }
                        case .cancel: return nil
                        default: break
                        }
                    }
                default:
                    if focus == .path { path.handle(key) }
                    else if focus == .name { name.handle(key) }
                    else if case .text(let text) = key {
                        if Date().timeIntervalSince(lastSearch) > 1 { quickSearch = "" }
                        quickSearch += text; lastSearch = Date()
                        if let match = browser.entries.firstIndex(where: { $0.name.lowercased().hasPrefix(quickSearch.lowercased()) }) {
                            selected = match
                            if !browser.entries[match].directory { chooseFile(browser.entries[match]) }
                        }
                        status = "Find: " + quickSearch
                    }
                }
            } catch { status = error.localizedDescription }
        }
    }
}
