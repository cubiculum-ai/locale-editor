import Foundation

public enum FieldKind: Equatable, Sendable {
    case text
    case format
    case integer(Int, Int)
    case grouping
    case week
    case strings(Int)
}

public struct FieldDefinition: Identifiable, Sendable {
    public let key: String
    public let label: String
    public let kind: FieldKind
    public let help: String
    public var id: String { key }

    public init(_ key: String, _ label: String, _ kind: FieldKind = .text, _ help: String = "") {
        self.key = key; self.label = label; self.kind = kind; self.help = help
    }

    public func parseInput(_ input: String) throws -> FieldValue {
        let value: FieldValue
        switch kind {
        case .text, .format: value = .text(input)
        case .integer:
            guard let n = Int(input.trimmingCharacters(in: .whitespaces)) else {
                throw LocaleEditorError("\(label) requires an integer.")
            }
            value = .integer(n)
        case .grouping, .week:
            var parts = input.trimmingCharacters(in: .whitespaces).split(separator: ";", omittingEmptySubsequences: false)
            if parts.count > 1 && parts.last?.isEmpty == true { parts.removeLast() }
            let values = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count == parts.count else { throw LocaleEditorError("Use group sizes such as 3;3 or 3;2, or -1 for no grouping.") }
            value = .integers(values)
        case .strings:
            value = .strings(input.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        try validate(value)
        return value
    }

    public func decodeSource(_ source: String, escape: Character) throws -> FieldValue {
        // glibc's country_isbn accepts both historical integer syntax and a quoted string.
        if key == "country_isbn", let number = Int64(source.trimmingCharacters(in: .whitespaces)) { return .text(String(number)) }
        switch kind {
        case .text, .format: return .text(try SourceSyntax.unquote(source, escape: escape))
        case .strings:
            return .strings(try SourceSyntax.splitValues(source, escape: escape).map { try SourceSyntax.unquote($0, escape: escape) })
        case .integer, .grouping, .week: return try parseInput(source)
        }
    }

    public func validate(_ value: FieldValue) throws {
        switch (kind, value) {
        case (.text, .text(let s)), (.format, .text(let s)):
            try Self.validateText(s)
            if kind == .format { try Self.validateFormat(s) }
            if key == "decimal_point", s.unicodeScalars.count != 1 {
                throw LocaleEditorError("\(label) must be exactly one Unicode scalar.")
            }
            if key == "mon_decimal_point", s.unicodeScalars.count > 1 { throw LocaleEditorError("\(label) must be empty or one Unicode scalar.") }
            if ["thousands_sep", "mon_thousands_sep"].contains(key), s.unicodeScalars.count > 1 {
                throw LocaleEditorError("\(label) must be empty or one Unicode scalar.")
            }
            if key == "int_curr_symbol", !s.isEmpty && (s.utf8.count != 4 || !s.prefix(3).utf8.allSatisfy({ (65...90).contains($0) }) || s.last != " ") {
                throw LocaleEditorError("International currency must be three uppercase letters and a trailing space, e.g. 'EUR '.")
            }
        case (.integer(let min, let max), .integer(let n)):
            let monetarySentinel = ["frac_digits", "int_frac_digits", "p_cs_precedes", "p_sep_by_space", "p_sign_posn", "n_cs_precedes", "n_sep_by_space", "n_sign_posn"].contains(key) && (n == -1 || n == 127)
            guard (min...max).contains(n) || monetarySentinel else { throw LocaleEditorError("\(label) must be between \(min) and \(max).") }
        case (.grouping, .integers(let values)):
            guard !values.isEmpty, values.count <= 16,
                  values.enumerated().allSatisfy({ index, n in (1...127).contains(n) || (index == values.count - 1 && (n == 0 || n == -1)) }) else {
                throw LocaleEditorError("Use group sizes 1–127; only the final item may be 0 (repeat) or -1 (stop).")
            }
        case (.week, .integers(let values)):
            guard values.count == 3, values[0] == 7, [19971130, 19971201].contains(values[1]), (1...7).contains(values[2]) else {
                throw LocaleEditorError("Use 7;19971130;4 for a Sunday-based day list and a four-day first week. Monday-based lists use 19971201.")
            }
        case (.strings(let count), .strings(let strings)):
            guard strings.count == count else { throw LocaleEditorError("\(label) needs \(count) entries separated by |.") }
            for s in strings { try Self.validateText(s) }
        default: throw LocaleEditorError("Wrong value type for \(label).")
        }
    }

    private static func validateText(_ s: String) throws {
        guard s.utf8.count <= 4096, !s.unicodeScalars.contains(where: { $0.value < 32 || (0x7F...0x9F).contains($0.value) }) else {
            throw LocaleEditorError("Values must be at most 4096 UTF-8 bytes and contain no control characters.")
        }
    }

    public static func formatConversions(_ s: String) throws -> [Character] {
        let chars = Array(s)
        var i = 0
        var conversions: [Character] = []
        while i < chars.count {
            guard chars[i] == "%" else { i += 1; continue }
            i += 1
            while i < chars.count && "_-0^#123456789:".contains(chars[i]) { i += 1 }
            if i < chars.count && "EO".contains(chars[i]) { i += 1 }
            guard i < chars.count else {
                throw LocaleEditorError("Invalid or incomplete strftime conversion in '\(s)'.")
            }
            conversions.append(chars[i]); i += 1
        }
        return conversions
    }
    private static func validateFormat(_ s: String) throws { _ = try formatConversions(s) }
}

public enum FieldSchema {
    public static func field(_ category: LocaleCategory, _ key: String) -> FieldDefinition? {
        fields(for: category).first { $0.key == key }
    }

    public static func fields(for category: LocaleCategory) -> [FieldDefinition] {
        switch category {
        case .time:
            return [
                .init("d_fmt", "Date format", .format, "strftime syntax: %Y-%m-%d → 2026-10-27"),
                .init("t_fmt", "Time format", .format, "%H:%M:%S → 17:04:05; %I:%M %p → 05:04 PM"),
                .init("d_t_fmt", "Date and time", .format),
                .init("date_fmt", "GNU date format", .format),
                .init("t_fmt_ampm", "12-hour time", .format),
                .init("am_pm", "AM / PM labels", .strings(2), "Two entries separated by |; empty labels are allowed."),
                .init("first_weekday", "First weekday", .integer(1, 7), "Offset into the inherited week base: usually 1 = Sunday, 2 = Monday."),
                .init("first_workday", "First workday", .integer(1, 7)),
                .init("day", "Weekday names", .strings(7), "Seven names separated by |, in inherited order (normally Sunday first)."),
                .init("abday", "Short weekday names", .strings(7)),
                .init("mon", "Month names", .strings(12)),
                .init("abmon", "Short month names", .strings(12)),
                .init("week", "Week definition", .week, "Days;day-list base date;minimum days in week 1. Keep the inherited base; ISO weeks need four days."),
            ]
        case .numeric:
            return [.init("decimal_point", "Decimal separator"), .init("thousands_sep", "Grouping separator"),
                    .init("grouping", "Digit grouping", .grouping, "3;3 → 1,234,567; 3;2 → 12,34,567; -1 disables grouping.")]
        case .monetary:
            var fields: [FieldDefinition] = [
                .init("currency_symbol", "Currency symbol"),
                .init("int_curr_symbol", "International currency", .text, "ISO currency code with a trailing space: EUR "),
                .init("mon_decimal_point", "Decimal separator"), .init("mon_thousands_sep", "Grouping separator"),
                .init("mon_grouping", "Digit grouping", .grouping),
                .init("frac_digits", "Decimal places", .integer(0, 20)),
                .init("int_frac_digits", "International decimal places", .integer(0, 20)),
                .init("positive_sign", "Positive sign"), .init("negative_sign", "Negative sign"),
            ]
            for (prefix, label) in [("p", "Positive"), ("n", "Negative")] {
                fields += [.init("\(prefix)_cs_precedes", "\(label): symbol before number", .integer(0, 1), "0 = after; 1 = before."),
                           .init("\(prefix)_sep_by_space", "\(label): spacing", .integer(0, 2), "0 = none; 1 = symbol/value; 2 = sign/symbol."),
                           .init("\(prefix)_sign_posn", "\(label): sign position", .integer(0, 4), "0 = parentheses; 1 = before all; 2 = after all; 3 = before symbol; 4 = after symbol.")]
            }
            return fields
        case .paper: return [.init("height", "Height (mm)", .integer(1, 10000)), .init("width", "Width (mm)", .integer(1, 10000))]
        case .measurement: return [.init("measurement", "Measurement system", .integer(1, 2), "1 = metric; 2 = US customary.")]
        case .telephone:
            return [
                .init("tel_int_fmt", "International format", .text, "%c country code; %a area code without trunk prefix; %l local number; punctuation is display-only."),
                .init("tel_dom_fmt", "Domestic format", .text, "%A area code with domestic prefix; %l local number; %e extension; %t conditional space."),
                .init("int_prefix", "Country calling code", .text, "Digits only in normal use, e.g. 43 for Austria; the format supplies +."),
                .init("int_select", "International access prefix", .text, "Outgoing dialing prefix used in this country, e.g. 00 or 011."),
            ]
        case .address:
            return [
                .init("postal_fmt", "Postal address format", .text, "%n name; %s street; %h house; %z postcode; %T city; %c country; %N conditional newline; %t conditional space."),
                .init("country_name", "Country name"), .init("country_post", "Postal country designation"),
                .init("country_ab2", "Country code (2 letters)"), .init("country_ab3", "Country code (3 letters)"),
                .init("country_num", "Numeric country code", .integer(0, 999)), .init("country_car", "Vehicle country code"),
                .init("country_isbn", "ISBN country group"), .init("lang_name", "Language name"),
                .init("lang_ab", "Language code (2 letters)"), .init("lang_term", "Language terminology code"),
                .init("lang_lib", "Language bibliographic code"),
            ]
        case .identification:
            return [
                .init("title", "Title", .text, "Descriptive title; use Rename locale to change the installable locale name."),
                .init("source", "Maintainer / organization"), .init("address", "Maintainer address"),
                .init("contact", "Contact person"), .init("email", "Email"),
                .init("tel", "Telephone (legacy)"), .init("fax", "Fax (legacy)"),
                .init("language", "Language"), .init("territory", "Territory"), .init("audience", "Audience"),
                .init("application", "Application"), .init("abbreviation", "Source abbreviation"),
                .init("revision", "Revision"), .init("date", "Revision date"),
            ]
        case .messages:
            return [.init("yesstr", "Yes label"), .init("nostr", "No label"),
                    .init("yesexpr", "Yes expression", .text, "POSIX extended regex, e.g. ^[yY]. A leading ^ anchors the response; expressions may overlap."),
                    .init("noexpr", "No expression", .text, "POSIX extended regex, e.g. ^[nN]. Live samples use glibc, not Swift regex syntax.")]
        case .name:
            return [.init("name_fmt", "Name format", .text, "%g given; %m additional; %f family; %F uppercase family; %d salutation; %t conditional space."),
                    .init("name_gen", "General salutation"), .init("name_mr", "Men's salutation"),
                    .init("name_mrs", "Married women's salutation"), .init("name_miss", "Unmarried women's salutation"),
                    .init("name_ms", "Women's salutation")]
        case .collate, .ctype: return []
        }
    }
}
