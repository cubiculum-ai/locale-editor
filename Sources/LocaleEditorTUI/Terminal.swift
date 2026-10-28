import Foundation
import LocaleCore
import LocaleRuntime
import CLocaleBridge
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum Key: Equatable {
    case up, down, left, right, home, end, pageUp, pageDown, enter, escape, tab, backTab
    case backspace, delete, clearLine, deleteWord, quit, tick, function(Int), text(String), mouse(MouseEvent), alt(String), location
}

final class Terminal {
    private var background = Screen()
    private var displayed = Screen()
    private struct EscapeInput {
        let introducer: UInt8
        var sequence = ""
        var invalid = false
        var legacy: [UInt8]?
    }
    private var pendingEscape: EscapeInput?
    init() throws {
        _ = setlocale(LC_CTYPE, "")
        #if os(Linux)
        _ = setlocale(LC_CTYPE, "C.UTF-8")
        #endif
        guard le_terminal_enter() == 0 else { throw LocaleEditorError("A terminal is required. Run locale-editor --help for noninteractive commands.") }
    }
    deinit { le_terminal_leave() }
    static func safe(_ text: String) -> String {
        text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
    }
    static func fit(_ text: String, width: Int) -> String {
        var used = 0, output = ""
        for char in safe(text) {
            let count = Screen.displayWidth(char)
            if used + count > max(0, width) { break }
            output.append(char); used += count
        }
        return output + String(repeating: " ", count: max(0, width - used))
    }
    func present(_ screen: Screen, cursor: (Int, Int)? = nil, remember: Bool = true) {
        if remember { background = screen }
        displayed = screen
        FileHandle.standardOutput.write(Data(screen.output(cursor: cursor).utf8))
    }
    func click(at event: MouseEvent) -> ClickAction? { displayed.click(at: event) }
    func scroll(at event: MouseEvent) -> ScrollArea? { displayed.scroll(at: event) }
    private func mouseKey(_ event: MouseEvent?) -> Key {
        guard let event else { return .tick }
        guard displayed.width == max(20, TerminalGeometry.columns - 1), displayed.height == max(8, TerminalGeometry.rows) else { return .tick }
        if case .function(let number) = displayed.click(at: event) { return .function(number) }
        return .mouse(event)
    }
    func draw(_ lines: [String]) {
        var screen = Screen()
        screen.box(x: 0, y: 1, width: screen.width, height: screen.height - 2, title: lines.first ?? "Locale Editor")
        for (row, line) in lines.dropFirst().enumerated() { screen.write(line, x: 2, y: row + 3, width: screen.width - 4) }
        present(screen)
    }
    private func byte() -> UInt8? {
        var value: UInt8 = 0
        return read(STDIN_FILENO, &value, 1) == 1 ? value : nil
    }
    func key() -> Key {
        if let pending = pendingEscape { return readEscape(pending) }
        guard let b = byte() else { return .tick }
        switch b {
        case 1: return .home
        case 5: return .end
        case 3, 4: return .quit
        case 9: return .tab
        case 12: return .location
        case 10, 13: return .enter
        case 8, 127: return .backspace
        case 21: return .clearLine
        case 23: return .deleteWord
        case 27:
            guard let next = byte() else { return .escape }
            if (48...57).contains(next) { return .function(next == 48 ? 10 : Int(next - 48)) }
            guard next == 91 || next == 79 else {
                if (32...126).contains(next) { return .alt(String(UnicodeScalar(next)).lowercased()) }
                return .escape
            }
            return readEscape(EscapeInput(introducer: next))
        case 0..<32: return .tick
        default:
            var bytes = [b]
            let length = b < 128 ? 1 : b < 224 ? 2 : b < 240 ? 3 : 4
            for _ in 1..<length { if let c = byte() { bytes.append(c) } }
            guard let text = String(bytes: bytes, encoding: .utf8) else { return .tick }
            return .text(text)
        }
    }

    /// Retain partial reports across reads: SSH may split an escape sequence between packets.
    private func readEscape(_ initial: EscapeInput) -> Key {
        var input = initial
        if input.legacy != nil {
            while input.legacy!.count < 3 {
                guard let c = byte() else { pendingEscape = input; return .tick }
                input.legacy!.append(c)
            }
            pendingEscape = nil
            return mouseKey(MouseEvent.legacy(input.legacy!))
        }
        for _ in 0..<64 {
            guard let c = byte() else { pendingEscape = input; return .tick }
            if c < 32 { pendingEscape = nil; return .tick }
            if input.sequence.utf8.count < 64 { input.sequence.append(Character(UnicodeScalar(c))) }
            else { input.invalid = true }
            guard (64...126).contains(c) else { continue }
            pendingEscape = nil
            guard !input.invalid else { return .tick }
            if input.introducer == 91 && input.sequence.hasPrefix("<") { return mouseKey(MouseEvent.sgr(input.sequence)) }
            if input.introducer == 91 && input.sequence == "M" {
                input.legacy = []
                return readEscape(input)
            }
            switch input.sequence {
            case "A": return .up
            case "B": return .down
            case "C": return .right
            case "D": return .left
            case "Z": return .backTab
            case "H", "1~", "7~": return .home
            case "F", "4~", "8~": return .end
            case "3~": return .delete
            case "5~": return .pageUp
            case "6~": return .pageDown
            case "P", "11~": return .function(1)
            case "Q", "12~": return .function(2)
            case "R", "13~": return .function(3)
            case "S", "14~": return .function(4)
            case "15~": return .function(5)
            case "17~": return .function(6)
            case "18~": return .function(7)
            case "19~": return .function(8)
            case "20~": return .function(9)
            case "21~": return .function(10)
            default: return .tick
            }
        }
        pendingEscape = input
        return .tick
    }

    func backdrop() -> Screen {
        if background.width == max(20, TerminalGeometry.columns - 1), background.height == max(8, TerminalGeometry.rows) {
            var screen = background
            screen.clearTargets() // a modal must never dispatch clicks to the panels behind it
            return screen
        }
        return Screen()
    }
    func prompt(_ title: String, initial: String = "", help: String = "", exampleTitle: String = "Illustrative example", multilineExample: Bool = false, example: ((String) -> String)? = nil) -> String? {
        var chars = Array(initial), cursor = chars.count, offset = 0
        var sample = "", sampled: String?, changed = Date.distantPast, redraw = true, oldSize = ""
        var inputLeft = 0
        while true {
            let input = String(chars)
            if let example, sampled != input, Date().timeIntervalSince(changed) > 0.12 {
                sample = example(input); sampled = input; redraw = true
            }
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            if redraw || size != oldSize {
                var screen = backdrop()
                let previewRows = multilineExample ? max(1, min(6, screen.height - 14)) : 1
                let w = min(screen.width - 4, 110), h = example == nil ? 10 : 12 + previewRows
                let x = max(0, (screen.width - w) / 2), y = max(1, (screen.height - h) / 2)
                screen.box(x: x, y: y, width: w, height: h, title: title, dialog: true)
                let inputWidth = w - 6
                inputLeft = x + 3
                if cursor < offset { offset = cursor }
                while offset < cursor && Screen.displayWidth(String(chars[offset..<cursor])) >= inputWidth - 1 { offset += 1 }
                screen.write(String(chars.dropFirst(offset)), x: x + 3, y: y + 3, width: inputWidth, ink: .input)
                screen.clickTarget(.input, x: x + 3, y: y + 3, width: inputWidth)
                screen.write(help, x: x + 3, y: y + 5, width: inputWidth, ink: .dialog)
                if example != nil {
                    screen.write(exampleTitle, x: x + 3, y: y + 7, width: inputWidth, ink: .dialog)
                    let lines = sampled == input ? (multilineExample ? sample.components(separatedBy: "\n") : [sample]) : ["Updating example…"]
                    for row in 0..<previewRows { screen.write(row < lines.count ? lines[row] : "", x: x + 3, y: y + 8 + row, width: inputWidth, ink: .input) }
                }
                screen.write("Enter: accept   Esc: cancel   Home/End   Ctrl-U: clear", x: x + 3, y: y + h - 3, width: inputWidth, ink: .dialog)
                screen.button("OK", x: x + 3, y: y + h - 2, action: .accept)
                screen.button("Cancel", x: x + 13, y: y + h - 2, action: .cancel)
                screen.functionBar(["", "OK", "", "", "", "", "", "", "", "Cancel"])
                let column = x + 3 + Screen.displayWidth(String(chars[offset..<cursor]))
                present(screen, cursor: (column, y + 3), remember: false)
                oldSize = size
            }
            let key = key(); redraw = key != .tick
            let before = String(chars)
            switch key {
            case .enter, .function(2): return String(chars)
            case .escape, .quit, .function(10): return nil
            case .left: cursor = max(0, cursor - 1)
            case .right: cursor = min(chars.count, cursor + 1)
            case .home: cursor = 0
            case .end: cursor = chars.count
            case .backspace: if cursor > 0 { chars.remove(at: cursor - 1); cursor -= 1 }
            case .delete: if cursor < chars.count { chars.remove(at: cursor) }
            case .clearLine: chars.removeAll(); cursor = 0; offset = 0
            case .deleteWord:
                while cursor > 0 && chars[cursor - 1].isWhitespace { chars.remove(at: cursor - 1); cursor -= 1 }
                while cursor > 0 && !chars[cursor - 1].isWhitespace { chars.remove(at: cursor - 1); cursor -= 1 }
            case .text(let s): if chars.count + s.count <= 8192 { chars.insert(contentsOf: s, at: cursor); cursor += s.count }
            case .mouse(let event):
                switch click(at: event) {
                case .input: cursor = Screen.cursorIndex(in: chars, offset: offset, column: event.x - inputLeft)
                case .accept: return String(chars)
                case .cancel: return nil
                default: break
                }
            default: break
            }
            if before != String(chars) { changed = Date() }
        }
    }

    func choose(_ title: String, choices: [PopupChoice], initial: String, subtitle: String = "", columnTitles: (String, String) = ("Definition / symbol", "Formatted example")) -> String? {
        var query = "", selected = choices.firstIndex { $0.id == initial } ?? 0
        var redraw = true, oldSize = "", offset = 0
        while true {
            let filtered = choices.filter { query.isEmpty || $0.id == "__custom__" || $0.searchable.localizedCaseInsensitiveContains(query) }
            selected = min(max(0, selected), max(0, filtered.count - 1))
            let previewRows = min(7, choices.map { $0.previewLines.count }.max() ?? 0)
            let reserved = previewRows > 0 ? previewRows + 1 : 0
            let count = max(3, TerminalGeometry.rows - 13 - reserved)
            offset = min(offset, max(0, filtered.count - count))
            if selected < offset { offset = selected }
            if selected >= offset + count { offset = selected - count + 1 }
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            if redraw || size != oldSize {
                var screen = backdrop()
                let w = min(screen.width - 4, 140), h = min(screen.height - 2, count + 11 + reserved)
                let x = max(0, (screen.width - w) / 2), y = max(1, (screen.height - h) / 2)
                screen.box(x: x, y: y, width: w, height: h, title: title, dialog: true)
                screen.scrollTarget(.choices, x: x + 1, y: y + 1, width: w - 2, height: h - 2)
                screen.write("Search: " + query, x: x + 2, y: y + 2, width: w - 4, ink: .input)
                screen.write(subtitle, x: x + 2, y: y + 3, width: w - 4, ink: .dialog)
                let split = max(12, (w - 6) / 2)
                screen.write(columnTitles.0, x: x + 2, y: y + 4, width: split, ink: .dialog)
                screen.write(columnTitles.1, x: x + 3 + split, y: y + 4, width: w - split - 5, ink: .dialog)
                for index in offset..<min(filtered.count, offset + count) {
                    let row = y + 5 + index - offset, item = filtered[index]
                    let ink: Ink = index == selected ? .selected : .dialog
                    screen.write((index == selected ? "> " : "  ") + item.label, x: x + 2, y: row, width: split, ink: ink)
                    screen.write(item.example, x: x + 3 + split, y: row, width: w - split - 5, ink: ink)
                    screen.clickTarget(.choice(index), x: x + 2, y: row, width: w - 4)
                }
                if !filtered.isEmpty {
                    if previewRows > 0 {
                        screen.write("Formatted postal address (illustrative components)", x: x + 2, y: y + 5 + count, width: w - 4, ink: .dialog)
                        for (row, line) in filtered[selected].previewLines.prefix(previewRows).enumerated() {
                            screen.write(line, x: x + 3, y: y + 6 + count + row, width: w - 6, ink: .input)
                        }
                    }
                    screen.write(filtered[selected].label, x: x + 2, y: y + h - 4, width: w - 4, ink: .dialog)
                    screen.write(filtered[selected].detail, x: x + 2, y: y + h - 3, width: w - 4, ink: .dialog)
                }
                screen.write("\(filtered.count) choices · Wheel ↑↓", x: x + 2, y: y + h - 2, width: 23, ink: .dialog)
                screen.button("Select", x: x + 26, y: y + h - 2, action: .accept)
                let hasCustom = choices.contains { $0.id == "__custom__" }
                if hasCustom { screen.button("Custom", x: x + 39, y: y + h - 2, action: .function(4)) }
                screen.button("Cancel", x: x + 52, y: y + h - 2, action: .cancel)
                screen.functionBar(["", "Select", "", hasCustom ? "Custom" : "", "", "", "", "", "", "Cancel"])
                present(screen, remember: false); oldSize = size
            }
            let key = key(); redraw = key != .tick
            switch key {
            case .escape, .quit, .function(10): return nil
            case .function(4): if choices.contains(where: { $0.id == "__custom__" }) { return "__custom__" }
            case .enter, .function(2): if !filtered.isEmpty { return filtered[selected].id }
            case .up: selected = max(0, selected - 1)
            case .down: selected = min(filtered.count - 1, selected + 1)
            case .pageUp: selected = max(0, selected - count)
            case .pageDown: selected = min(filtered.count - 1, selected + count)
            case .home: selected = 0
            case .end: selected = filtered.count - 1
            case .clearLine: query = ""; selected = 0; offset = 0
            case .backspace: if !query.isEmpty { query.removeLast(); selected = 0; offset = 0 }
            case .text(let s): query += s; selected = 0; offset = 0
            case .mouse(let event):
                if case .wheel(let direction) = event.kind, scroll(at: event) == .choices {
                    offset = min(max(0, filtered.count - count), max(0, offset + direction * 3))
                    selected = min(max(0, filtered.count - 1), min(offset + count - 1, max(offset, selected)))
                } else {
                    switch click(at: event) {
                    case .choice(let index) where filtered.indices.contains(index): return filtered[index].id
                    case .accept: if !filtered.isEmpty { return filtered[selected].id }
                    case .cancel: return nil
                    default: break
                    }
                }
            default: break
            }
        }
    }
    func choose(_ title: String, names: [String], initial: String) -> String? {
        choose(title, choices: names.map { PopupChoice(id: $0, label: $0, example: "") }, initial: initial, subtitle: "Type to search; existing field overrides are retained.")
    }
    func page(_ title: String, lines: [String]) {
        var offset = 0, redraw = true, oldSize = ""
        while true {
            let count = max(3, TerminalGeometry.rows - 6)
            offset = min(offset, max(0, lines.count - count))
            let size = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            if redraw || size != oldSize {
                var screen = backdrop()
                screen.box(x: 1, y: 1, width: screen.width - 2, height: screen.height - 3, title: title)
                screen.scrollTarget(.page, x: 2, y: 2, width: screen.width - 4, height: screen.height - 5)
                for (i, line) in lines.dropFirst(offset).prefix(count).enumerated() { screen.write(line, x: 3, y: 3 + i, width: screen.width - 6) }
                screen.write("↑↓ PgUp/PgDn scroll · q / Esc return · \(offset + 1)/\(max(1, lines.count))", x: 2, y: screen.height - 2, width: screen.width - 4, ink: .status)
                screen.functionBar(["", "", "", "", "", "", "", "", "", "Close"])
                present(screen, remember: false); oldSize = size
            }
            let key = key(); redraw = key != .tick
            switch key {
            case .escape, .quit, .text("q"), .enter, .function(10): return
            case .up: offset = max(0, offset - 1)
            case .down: offset = min(max(0, lines.count - count), offset + 1)
            case .pageUp: offset = max(0, offset - count)
            case .pageDown: offset = min(max(0, lines.count - count), offset + count)
            case .home: offset = 0
            case .end: offset = max(0, lines.count - count)
            case .mouse(let event):
                if case .wheel(let direction) = event.kind, scroll(at: event) == .page { offset = min(max(0, lines.count - count), max(0, offset + direction * 3)) }
            default: break
            }
        }
    }
}
