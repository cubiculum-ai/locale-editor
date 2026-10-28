import Foundation

public enum SourceSyntax {
    /// All output uses / as escape character. Unicode is serialized unambiguously as symbols.
    public static func quote(_ value: String) -> String {
        "\"" + value.unicodeScalars.map { scalar in
            let n = scalar.value
            if n >= 32 && n < 127 && ![34, 47, 60, 62].contains(n) { return String(scalar) }
            return String(format: n <= 0xFFFF ? "<U%04X>" : "<U%08X>", n)
        }.joined() + "\""
    }

    public static func splitValues(_ source: String, escape: Character) throws -> [String] {
        var parts: [String] = [], current = "", quoted = false, escaped = false
        for c in source {
            if escaped { current.append(c); escaped = false; continue }
            if c == escape { current.append(c); escaped = true; continue }
            if c == "\"" { quoted.toggle() }
            if c == ";" && !quoted { parts.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(c) }
        }
        guard !quoted, !escaped else { throw LocaleEditorError("Unterminated quoted value: \(source)") }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        if parts.count > 1 && parts.last == "" { parts.removeLast() }
        return parts
    }

    public static func unquote(_ source: String, escape: Character) throws -> String {
        let source = source.trimmingCharacters(in: .whitespaces)
        guard source.first == "\"", source.last == "\"", source.count >= 2 else {
            throw LocaleEditorError("Expected a quoted locale string: \(source)")
        }
        let chars = Array(source.dropFirst().dropLast())
        var result = "", i = 0
        while i < chars.count {
            if chars[i] == escape {
                i += 1
                guard i < chars.count else { throw LocaleEditorError("Dangling escape in locale string.") }
                // Numeric byte escapes require a charmap; do not silently reinterpret them.
                if "dx01234567".contains(chars[i]) { throw LocaleEditorError("Numeric byte escapes are not editable yet; keep this field inherited.") }
                result.append(chars[i]); i += 1
            } else if chars[i] == "<" {
                guard let end = chars[i...].firstIndex(of: ">") else { throw LocaleEditorError("Unterminated character symbol.") }
                let symbol = String(chars[(i + 1)..<end])
                guard symbol.first == "U", (5...9).contains(symbol.count),
                      let code = UInt32(symbol.dropFirst(), radix: 16), let scalar = UnicodeScalar(code) else {
                    throw LocaleEditorError("Unsupported character symbol <\(symbol)>; keep this field inherited.")
                }
                result.unicodeScalars.append(scalar); i = end + 1
            } else {
                guard chars[i] != "\"" else { throw LocaleEditorError("Unexpected quote in locale string.") }
                result.append(chars[i]); i += 1
            }
        }
        return result
    }

    static func stripComment(_ line: String, comment: Character, escape: Character, quoted: inout Bool) -> String {
        var result = "", escaped = false
        for c in line {
            if escaped { result.append(c); escaped = false; continue }
            if c == escape { result.append(c); escaped = true; continue }
            if c == "\"" { quoted.toggle() }
            if c == comment && !quoted { break }
            result.append(c)
        }
        return result
    }

    static func canonicalize(_ line: String, escape: Character) -> String {
        var result = "", escaped = false
        for c in line {
            if escaped { result.append("/"); result.append(c); escaped = false }
            else if c == escape { escaped = true }
            else if c == "/" { result += "//" }
            else { result.append(c) }
        }
        if escaped { result.append("/") }
        return result
    }
}

public struct SourceEntry: Equatable, Sendable {
    public let keyword: String
    public let value: String
    public let line: Int
    public var text: String { keyword + (value.isEmpty ? "" : " " + value) }
}

public struct SourceSection: Sendable {
    public let category: LocaleCategory
    public let entries: [SourceEntry]
    public let escape: Character
    public let origin: String
    public func entry(_ key: String) -> SourceEntry? { entries.first { $0.keyword == key } }
}

public struct LocaleSource: Sendable {
    public let name: String
    public let sections: [LocaleCategory: SourceSection]

    public static func parse(_ text: String, name: String) throws -> Self {
        var escape: Character = "\\", comment: Character = "#"
        var sections: [LocaleCategory: SourceSection] = [:]
        var category: LocaleCategory?, entries: [SourceEntry] = []
        var pending = "", pendingLine = 0, quoted = false
        for (index, physical) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            let trimmed = physical.trimmingCharacters(in: .whitespaces)
            // Header declarations must be processed before comment stripping.
            if category == nil && pending.isEmpty {
                let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                if parts.count == 2, ["escape_char", "comment_char"].contains(String(parts[0])) {
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    guard value.count == 1, let char = value.first else { throw LocaleEditorError("\(name):\(index + 1): invalid syntax character.") }
                    if parts[0] == "escape_char" { escape = char } else { comment = char }
                    continue
                }
            }
            // Carry quote state across continuations without repeatedly rescanning long CTYPE lists.
            var line = SourceSyntax.stripComment(physical, comment: comment, escape: escape, quoted: &quoted)
            if pending.isEmpty { pendingLine = index + 1 }
            let trailing = physical.reversed().prefix { $0 == escape }.count
            if trailing % 2 == 1 {
                if line.last == escape { line.removeLast() }
                pending += line; continue
            }
            line = (pending + line).trimmingCharacters(in: .whitespaces)
            pending = ""; quoted = false
            guard !line.isEmpty else { continue }
            if let newCategory = LocaleCategory(rawValue: line) {
                guard category == nil, sections[newCategory] == nil else { throw LocaleEditorError("\(name):\(pendingLine): nested or duplicate section.") }
                category = newCategory; entries = []; continue
            }
            if line.hasPrefix("END ") || line.hasPrefix("END\t") {
                guard let current = category, line.split(whereSeparator: \.isWhitespace).map(String.init) == ["END", current.rawValue] else {
                    throw LocaleEditorError("\(name):\(pendingLine): mismatched section end.")
                }
                sections[current] = SourceSection(category: current, entries: entries, escape: escape, origin: name)
                category = nil; entries = []; continue
            }
            guard category != nil else { continue } // supplementary source files may contain top-level directives
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            entries.append(SourceEntry(keyword: String(parts[0]), value: parts.count == 2 ? String(parts[1]) : "", line: pendingLine))
        }
        guard category == nil, pending.isEmpty else { throw LocaleEditorError("\(name): unfinished section or continued line.") }
        return Self(name: name, sections: sections)
    }
}
