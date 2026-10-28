import Foundation

public struct ConventionPreset: Sendable {
    public let label: String
    public let value: FieldValue
    public let note: String
    public let related: [String: FieldValue]
    public init(_ label: String, _ value: FieldValue, _ note: String, related: [String: FieldValue] = [:]) {
        self.label = label; self.value = value; self.note = note; self.related = related
    }
}

/// Explicit curated choices precede source-derived definitions in every frontend.
/// A standard may permit alternatives; this is not a claim of whole-locale certification.
public enum InternationalConventions {
    public static func presets(category: LocaleCategory, field: String, values: [String: FieldValue]) -> [ConventionPreset] {
        let iso = "International standard · ISO 8601"
        switch (category, field) {
        case (.time, "d_fmt"):
            return [.init(iso + " · calendar date", .text("%Y-%m-%d"), "Year-month-day, Gregorian calendar."),
                    .init(iso + " · week date", .text("%G-W%V-%u"), "ISO week-year, week number and Monday=1 weekday; may differ from calendar year around New Year."),
                    .init(iso + " · ordinal date", .text("%Y-%j"), "Year and day of year, 001–366."),
                    .init(iso + " · basic date", .text("%Y%m%d"), "Compact calendar date.")]
        case (.time, "t_fmt"):
            return [.init(iso + " · 24-hour time", .text("%H:%M:%S"), "Local clock time; timezone is not specified by this value.")]
        case (.time, "d_t_fmt"), (.time, "date_fmt"):
            var result = [ConventionPreset(iso + " · local date/time", .text("%Y-%m-%dT%H:%M:%S"), "Local date/time without a UTC offset; no literal Z is added.")]
            if field == "date_fmt" {
                result.insert(.init(iso + " · with UTC offset", .text("%Y-%m-%dT%H:%M:%S%:z"), "GNU date supports %:z. The actual timezone offset is used, not a hard-coded Z."), at: 0)
            }
            result.append(.init(iso + " · basic, with UTC offset", .text("%Y%m%dT%H%M%S%z"), "Basic ISO date/time and numeric UTC offset; supported by glibc strftime."))
            return result
        case (.time, "week"), (.time, "first_weekday"):
            let week = isoWeek(values)
            let monday = mondayOffset(values)
            return [.init(iso + " · Monday / four-day first week", field == "week" ? week : .integer(monday),
                          "Preserves the day-list base and translated day names; sets Monday and a minimum of four days in week 1.",
                          related: ["week": week, "first_weekday": .integer(monday)])]
        case (.numeric, "decimal_point"):
            return [.init("International standard · SI · decimal point", .text("."), "SI permits either point or comma. Neither is a universal requirement."),
                    .init("International standard · SI · decimal comma", .text(","), "Equally permitted by SI; choose for the language/context.")]
        case (.numeric, "thousands_sep"):
            return [.init("International standard · SI · space grouping", .text("\u{202F}"), "Groups of three separated by a space; uses U+202F NARROW NO-BREAK SPACE.", related: ["grouping": .integers([3, 3])]),
                    .init("International standard · SI · no grouping", .text(""), "Grouping is optional.", related: ["grouping": .integers([-1])]),
                    .init("International standard · SI · plain space", .text(" "), "ASCII-space alternative, groups of three.", related: ["grouping": .integers([3, 3])])]
        case (.numeric, "grouping"):
            return [.init("International standard · SI · groups of three", .integers([3, 3]), "Also sets a narrow nonbreaking space separator; glibc cannot omit grouping only for four-digit numbers.", related: ["thousands_sep": .text("\u{202F}")]),
                    .init("International standard · SI · no grouping", .integers([-1]), "Grouping is optional.")]
        case (.measurement, "measurement"):
            return [.init("International standard · SI · metric", .integer(1), "glibc's metric flag. Applications choose which units to display; this does not convert stored quantities.")]
        case (.monetary, "currency_symbol"):
            return [.init("¤ · Generic currency · Unicode U+00A4", .text("¤"), "Generic or unknown currency sign, not a monetary unit or an ISO currency code. The international currency code is unchanged.")]
        case (.monetary, "int_curr_symbol"):
            return [.init("International standard · ISO 4217 · XXX", .text("XXX "), "No currency is involved. Not a generic substitute for an actual monetary unit; selecting ¤ alone leaves this code unchanged.")]
        case (.telephone, "tel_int_fmt"):
            return [.init("International standard · ITU E.164 / E.123 · compact", .text("+%c%a%l"), "+ followed by country code and national significant number. Actual numbers need valid numbering-plan components (at most 15 digits); no domestic trunk prefix."),
                    .init("International standard · ITU E.123 · spaced", .text("+%c %a %l"), "Readable international display. Parentheses are not used for international notation.")]
        case (.name, "name_fmt"):
            return [.init("Given and family names · no salutation", .text("%g%t%m%t%f"), "Convenience preset, not a universal international name-order standard."),
                    .init("Family, given names", .text("%f, %g%t%m"), "Convenience preset; actual personal-name ordering varies.")]
        default: return []
        }
    }

    private static func mondayOffset(_ values: [String: FieldValue]) -> Int {
        if case .integers(let week) = values["week"], week.count == 3, week[1] == 19971201 { return 1 }
        return 2
    }
    private static func isoWeek(_ values: [String: FieldValue]) -> FieldValue {
        .integers([7, mondayOffset(values) == 1 ? 19971201 : 19971130, 4])
    }

    public static func changes(project: LocaleProject, catalog: LocaleCatalog, genericCurrency: Bool) throws -> [LocaleCategory: [String: FieldValue]] {
        let time = try catalog.effectiveValues(.time, project: project)
        let numeric = try catalog.effectiveValues(.numeric, project: project)
        let decimal = numeric["decimal_point"] == .text(",") ? "," : "."
        let separator = FieldValue.text("\u{202F}")
        let grouping = FieldValue.integers([3, 3])
        var result: [LocaleCategory: [String: FieldValue]] = [
            .time: ["d_fmt": .text("%Y-%m-%d"), "t_fmt": .text("%H:%M:%S"), "d_t_fmt": .text("%Y-%m-%dT%H:%M:%S"),
                    "date_fmt": .text("%Y-%m-%dT%H:%M:%S%:z"), "week": isoWeek(time), "first_weekday": .integer(mondayOffset(time))],
            .numeric: ["decimal_point": .text(decimal), "thousands_sep": separator, "grouping": grouping],
            .monetary: ["mon_thousands_sep": separator, "mon_grouping": grouping],
            .paper: ["width": .integer(210), "height": .integer(297)],
            .measurement: ["measurement": .integer(1)], .telephone: ["tel_int_fmt": .text("+%c%a%l")]
        ]
        if genericCurrency { result[.monetary]?["currency_symbol"] = .text("¤") }
        return result
    }

    public static let explanation = [
        "ISO 8601: YYYY-MM-DD, 24-hour local time, Monday and a four-day first week; GNU date includes the real UTC offset.",
        "SI: metric flag and space-separated groups of three. Both decimal point and comma are allowed; the current one is preserved.",
        "The same narrow nonbreaking space and groups of three are applied to money amounts, with either currency-symbol choice. Monetary decimal separators stay unchanged.",
        "ISO 216: A4, 210 × 297 mm. ITU E.164/E.123: compact +country-code + national significant number.",
        "The optional generic currency sign ¤ is a Unicode symbol, not an ISO monetary unit. The international currency code stays unchanged.",
        "Language, translated names, yes/no responses, postal layout, country calling code, sorting and character profile are preserved.",
        "There is no universal name order, postal layout, yes/no wording or country calling code to substitute. glibc locales affect only applications that consult them.",
        "This is a set of selected conventions, not whole-locale ISO certification. Changes are undoable together."
    ]
}
