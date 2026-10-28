import Foundation
import LocaleRuntime
import CLocaleBridge

enum Ink {
    case panel, bright, border, selected, selectedInactive, accent, menu, status, dialog, dialogBorder, input, muted, keyNumber, keyLabel, disabled, menuHotkey, menuHotkeyActive
    var ansi: String {
        let code: String
        switch self {
        case .panel: code = "0;37;44"
        case .bright: code = "1;37;44"
        case .border, .muted: code = "0;36;44"
        case .selectedInactive, .accent: code = "1;33;44"
        case .selected, .menu, .input, .keyLabel: code = "0;30;46"
        case .status, .dialog: code = "0;30;47"
        case .dialogBorder: code = "1;37;47"
        case .keyNumber: code = "0;37;40"
        case .disabled: code = "0;90;44"
        case .menuHotkey: code = "4;30;46"
        case .menuHotkeyActive: code = "1;4;33;44"
        }
        return "\u{1B}[" + code + "m"
    }
}

struct Screen {
    struct Cell { var text = " "; var ink: Ink = .panel }
    let width: Int
    let height: Int
    private var cells: [Cell]
    private var clickTargets: [(CellRect, ClickAction)] = []
    private var scrollTargets: [(CellRect, ScrollArea)] = []
    init(width: Int = TerminalGeometry.columns, height: Int = TerminalGeometry.rows) {
        self.width = max(20, width - 1); self.height = max(8, height)
        cells = Array(repeating: Cell(), count: self.width * self.height)
    }
    static func displayWidth(_ character: Character) -> Int {
        character.unicodeScalars.map { let w = Int(le_display_width($0.value)); return w < 0 ? 1 : w }.max() ?? 1
    }
    static func displayWidth(_ text: String) -> Int { text.reduce(0) { $0 + displayWidth($1) } }
    static func wrapped(_ text: String, width: Int) -> [String] {
        var lines: [String] = [], current = "", used = 0
        for character in text {
            if character.isNewline { lines.append(current); current = ""; used = 0; continue }
            let count = displayWidth(character)
            if used + count > max(1, width), !current.isEmpty { lines.append(current); current = ""; used = 0 }
            current.append(character); used += count
        }
        lines.append(current)
        return lines
    }
    static func cursorIndex(in characters: [Character], offset: Int, column: Int) -> Int {
        var index = min(max(0, offset), characters.count), used = 0
        while index < characters.count {
            let size = displayWidth(characters[index])
            if used + size > max(0, column) { break }
            used += size; index += 1
        }
        return index
    }
    mutating func clickTarget(_ action: ClickAction, x: Int, y: Int, width: Int, height: Int = 1) {
        clickTargets.append((CellRect(x: x, y: y, width: width, height: height), action))
    }
    mutating func scrollTarget(_ area: ScrollArea, x: Int, y: Int, width: Int, height: Int) {
        scrollTargets.append((CellRect(x: x, y: y, width: width, height: height), area))
    }
    func click(at event: MouseEvent) -> ClickAction? {
        guard event.isPrimaryPress else { return nil }
        return clickTargets.last { $0.0.contains(x: event.x, y: event.y) }?.1
    }
    func scroll(at event: MouseEvent) -> ScrollArea? {
        scrollTargets.last { $0.0.contains(x: event.x, y: event.y) }?.1
    }
    mutating func clearTargets() { clickTargets.removeAll(); scrollTargets.removeAll() }
    mutating func button(_ label: String, x: Int, y: Int, action: ClickAction) {
        let text = "[ " + label + " ]", width = Self.displayWidth(text)
        write(text, x: x, y: y, width: width, ink: .selected)
        clickTarget(action, x: x, y: y, width: width)
    }
    mutating func write(_ text: String, x: Int, y: Int, width limit: Int? = nil, ink: Ink = .panel) {
        guard y >= 0, y < height, x >= 0, x < width else { return }
        let end = min(width, x + (limit ?? width - x))
        guard end > x else { return }
        for i in x..<end { cells[y * width + i] = Cell(text: " ", ink: ink) }
        var column = x
        for character in Terminal.safe(text) {
            let count = Self.displayWidth(character)
            guard column + count <= end else { break }
            if count == 0 {
                if column > x { cells[y * width + column - 1].text.append(character) }
                continue
            }
            cells[y * width + column] = Cell(text: String(character), ink: ink)
            if count > 1 { for i in (column + 1)..<(column + count) { cells[y * width + i] = Cell(text: "", ink: ink) } }
            column += count
        }
    }
    mutating func box(x: Int, y: Int, width w: Int, height h: Int, title: String = "", dialog: Bool = false) {
        guard w >= 2, h >= 2 else { return }
        let border: Ink = dialog ? .dialogBorder : .border
        let fill: Ink = dialog ? .dialog : .panel
        for row in (y + 1)..<(y + h - 1) {
            write("│", x: x, y: row, width: 1, ink: border)
            write("", x: x + 1, y: row, width: w - 2, ink: fill)
            write("│", x: x + w - 1, y: row, width: 1, ink: border)
        }
        write("┌" + String(repeating: "─", count: w - 2) + "┐", x: x, y: y, width: w, ink: border)
        write("└" + String(repeating: "─", count: w - 2) + "┘", x: x, y: y + h - 1, width: w, ink: border)
        if !title.isEmpty { write(" " + title + " ", x: x + 2, y: y, width: min(w - 4, Self.displayWidth(title) + 2), ink: dialog ? .dialog : .bright) }
    }
    mutating func functionBar(_ labels: [String]) {
        var x = 0
        for (index, label) in labels.enumerated() {
            let next = (index + 1) * width / labels.count
            if !label.isEmpty { clickTarget(.function(index + 1), x: x, y: height - 1, width: next - x) }
            let number = String(index + 1)
            write(label.isEmpty ? "" : number, x: x, y: height - 1, width: number.count, ink: .keyNumber)
            x += number.count
            write(label, x: x, y: height - 1, width: next - x, ink: .keyLabel)
            x = next
        }
    }
    func output(cursor: (Int, Int)? = nil) -> String {
        var result = "\u{1B}[?25l\u{1B}[H", ink: Ink?
        for y in 0..<height {
            for x in 0..<width {
                let cell = cells[y * width + x]
                if cell.ink != ink { result += cell.ink.ansi; ink = cell.ink }
                result += cell.text
            }
            result += "\u{1B}[K"
            if y < height - 1 { result += "\r\n" }
        }
        result += "\u{1B}[0m"
        if let (x, y) = cursor { result += "\u{1B}[\(y + 1);\(x + 1)H\u{1B}[?25h" }
        return result
    }
}

struct PopupChoice {
    let id: String
    let label: String
    let example: String
    var detail: String = ""
    var previewLines: [String] = []
    var searchable: String { label + " " + example + " " + detail }
}
