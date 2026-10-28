import Foundation

/// LC_PAPER stores integer millimetres. Inch-based media use their conventional rounded sizes.
public struct PaperSize: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let note: String
    public var isInternationalStandard: Bool { id.first == "a" || id.first == "b" }
    public var choiceLabel: String { isInternationalStandard ? name + " · International standard · ISO 216" : name }
    public var dimensions: String { "\(width) × \(height) mm" }
    public var overrides: [String: FieldValue] { ["width": .integer(width), "height": .integer(height)] }
}

public enum PaperSizes {
    // Standard names/dimensions: PWG 5101.1; fax-safe is an application-specific custom size.
    private static let sizes: [PaperSize] = [
        .init(id: "a4", name: "A4", width: 210, height: 297, note: "ISO A4"),
        .init(id: "letter", name: "US Letter", width: 216, height: 279, note: "8.5 × 11 in; nominal 215.9 × 279.4 mm, rounded for glibc"),
        .init(id: "fax-safe", name: "Fax-safe", width: 210, height: 279, note: "A4 width and no taller than US Letter; 279.4 mm rounded down to 279 mm"),
        .init(id: "legal", name: "US Legal", width: 216, height: 356, note: "8.5 × 14 in, rounded to whole millimetres"),
        .init(id: "tabloid", name: "Tabloid", width: 279, height: 432, note: "11 × 17 in, rounded to whole millimetres"),
        .init(id: "ledger", name: "Ledger", width: 432, height: 279, note: "17 × 11 in, rounded to whole millimetres"),
        .init(id: "executive", name: "Executive (7.25 × 10.5 in)", width: 184, height: 267, note: "Rounded to whole millimetres"),
        .init(id: "a0", name: "A0", width: 841, height: 1189, note: "ISO A0"),
        .init(id: "a1", name: "A1", width: 594, height: 841, note: "ISO A1"),
        .init(id: "a2", name: "A2", width: 420, height: 594, note: "ISO A2"),
        .init(id: "a3", name: "A3", width: 297, height: 420, note: "ISO A3"),
        .init(id: "a5", name: "A5", width: 148, height: 210, note: "ISO A5"),
        .init(id: "a6", name: "A6", width: 105, height: 148, note: "ISO A6"),
        .init(id: "a7", name: "A7", width: 74, height: 105, note: "ISO A7"),
        .init(id: "a8", name: "A8", width: 52, height: 74, note: "ISO A8"),
        .init(id: "a9", name: "A9", width: 37, height: 52, note: "ISO A9"),
        .init(id: "a10", name: "A10", width: 26, height: 37, note: "ISO A10"),
        .init(id: "b0", name: "ISO B0", width: 1000, height: 1414, note: "ISO B0"),
        .init(id: "b1", name: "ISO B1", width: 707, height: 1000, note: "ISO B1"),
        .init(id: "b2", name: "ISO B2", width: 500, height: 707, note: "ISO B2"),
        .init(id: "b3", name: "ISO B3", width: 353, height: 500, note: "ISO B3"),
        .init(id: "b4", name: "ISO B4", width: 250, height: 353, note: "ISO B4"),
        .init(id: "b5", name: "ISO B5", width: 176, height: 250, note: "ISO B5"),
        .init(id: "b6", name: "ISO B6", width: 125, height: 176, note: "ISO B6"),
        .init(id: "b7", name: "ISO B7", width: 88, height: 125, note: "ISO B7"),
        .init(id: "b8", name: "ISO B8", width: 62, height: 88, note: "ISO B8"),
        .init(id: "b9", name: "ISO B9", width: 44, height: 62, note: "ISO B9"),
        .init(id: "b10", name: "ISO B10", width: 31, height: 44, note: "ISO B10"),
        .init(id: "jis-b4", name: "JIS B4", width: 257, height: 364, note: "Japanese B4"),
        .init(id: "jis-b5", name: "JIS B5", width: 182, height: 257, note: "Japanese B5"),
    ]
    public static var all: [PaperSize] { sizes.filter(\.isInternationalStandard) + sizes.filter { !$0.isInternationalStandard } }
    public static func match(width: Int, height: Int) -> PaperSize? { all.first { $0.width == width && $0.height == height } }
    public static func name(values: [String: FieldValue]) -> String {
        guard case .integer(let width) = values["width"], case .integer(let height) = values["height"] else { return "Inherited / not specified" }
        if let size = match(width: width, height: height) { return size.name }
        if let size = match(width: height, height: width), size.id != "fax-safe" { return size.name + " (landscape)" }
        return "Custom"
    }
}
