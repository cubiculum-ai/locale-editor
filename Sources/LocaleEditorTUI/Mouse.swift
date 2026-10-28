import Foundation

/// Terminal coordinates are normalized to zero-based character cells, just like Screen.
struct MouseEvent: Equatable {
    enum Kind: Equatable { case press(Int), release, wheel(Int) }
    let x: Int
    let y: Int
    let kind: Kind
    var isPrimaryPress: Bool { kind == .press(0) }

    static func sgr(_ sequence: String) -> Self? {
        guard sequence.first == "<", let final = sequence.last, final == "M" || final == "m" else { return nil }
        let parts = sequence.dropFirst().dropLast().split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count == 3, let button = Int(parts[0]), let x = Int(parts[1]), let y = Int(parts[2]) else { return nil }
        return decode(button: button, x: x, y: y, release: final == "m")
    }
    static func legacy(_ bytes: [UInt8]) -> Self? {
        guard bytes.count == 3, bytes.allSatisfy({ $0 >= 32 }) else { return nil }
        return decode(button: Int(bytes[0]) - 32, x: Int(bytes[1]) - 32, y: Int(bytes[2]) - 32, release: false)
    }
    private static func decode(button: Int, x: Int, y: Int, release: Bool) -> Self? {
        guard (0...127).contains(button), (1...1_000_000).contains(x), (1...1_000_000).contains(y), button & 32 == 0 else { return nil }
        let kind: Kind
        if release || button & 3 == 3 && button & 64 == 0 { kind = .release }
        else if button & 64 != 0 {
            guard button & 3 < 2 else { return nil } // horizontal wheel is deliberately ignored
            kind = .wheel(button & 1 == 0 ? -1 : 1)
        } else { kind = .press(button & 3) }
        return Self(x: x - 1, y: y - 1, kind: kind)
    }
}

struct CellRect: Equatable {
    let x: Int, y: Int, width: Int, height: Int
    func contains(x px: Int, y py: Int) -> Bool {
        px >= x && py >= y && px < x + max(0, width) && py < y + max(0, height)
    }
}

enum ClickAction: Equatable {
    case function(Int), section(Int), field(Int), source, choice(Int), input, accept, cancel, menuHeading(Int), menuItem(Int)
    case fileEntry(Int), filePath, fileName, parentDirectory, homeDirectory, toggleHidden
}
enum ScrollArea: Equatable { case sections, fields, choices, page, menu, files }
