import Foundation

/// Fast illustrative samples for popup choices. Applied settings are always verified by glibc.
public enum FieldExamples {
    public static func example(_ field: FieldDefinition, category: LocaleCategory, values: [String: FieldValue]) -> String {
        if case .integer(let n) = values[field.key], n == -1 || n == 127 { return "Not specified (locale default)" }
        switch category {
        case .numeric: return number(values: values)
        case .monetary:
            var example = values
            if field.key.hasPrefix("int_") {
                example["currency_symbol"] = .text(text(values, "int_curr_symbol", "XXX ").trimmingCharacters(in: .whitespaces))
                example["frac_digits"] = values["int_frac_digits"]
            }
            return money(values: example, negative: field.key.hasPrefix("n_") || field.key == "negative_sign")
        case .paper: return "\(integer(values, "width", 210)) × \(integer(values, "height", 297)) mm"
        case .measurement: return integer(values, "measurement", 1) == 1 ? "Metric · metres, litres" : "US customary · feet, gallons"
        case .telephone: return TelephoneFormats.sample(field.key, values: values)
        case .name: return PersonalNames.sample(field.key, values: values)
        case .messages:
            if field.key.hasSuffix("expr") { return "POSIX regex · matching samples require Linux/glibc" }
            return text(values, "yesstr", "yes") + " / " + text(values, "nostr", "no")
        case .address where field.key == "postal_fmt": return PostalAddresses.lines(values: values).joined(separator: " ↵ ")
        case .time:
            if field.key == "week", case .integers(let week) = values[field.key], week.count == 3 {
                return "7 days · day-list base " + (week[1] == 19971201 ? "Monday" : "Sunday") + " · week 1 needs \(week[2]) days"
            }
            if ["first_weekday", "first_workday"].contains(field.key) {
                let index = integer(values, field.key, field.key == "first_workday" ? 2 : 1) - 1
                if case .strings(let days) = values["day"], days.indices.contains(index) { return days[index] }
            }
            if case .strings(let strings) = values[field.key] { return strings.joined(separator: " · ") }
            return values[field.key]?.display ?? "(not specified)"
        default: return values[field.key]?.display ?? "(inherited)"
        }
    }

    public static func number(values: [String: FieldValue], monetary: Bool = false) -> String {
        let prefix = monetary ? "mon_" : ""
        let fraction = monetary ? min(20, max(0, integer(values, "frac_digits", 2))) : 2
        let decimal = text(values, prefix + "decimal_point", ".")
        let separator = text(values, prefix + "thousands_sep", ",")
        let grouping: [Int]
        if case .integers(let groups) = values[monetary ? "mon_grouping" : "grouping"] { grouping = groups } else { grouping = [3, 3] }
        var digits = "1234567", parts: [String] = [], index = 0, last = 0
        while !digits.isEmpty {
            // localedef source zero stops grouping; an exhausted list repeats its final size.
            let size = index < grouping.count ? grouping[index] : last
            guard size > 0, size < 127 else { parts.append(digits); break }
            let count = min(size, digits.count)
            parts.append(String(digits.suffix(count))); digits.removeLast(count)
            last = size; index += 1
        }
        let whole = parts.reversed().joined(separator: separator)
        return whole + (fraction > 0 ? decimal + String(("89" + String(repeating: "0", count: fraction)).prefix(fraction)) : "")
    }

    public static func money(values: [String: FieldValue], negative: Bool = false) -> String {
        let prefix = negative ? "n" : "p"
        let symbol = text(values, "currency_symbol", "¤")
        let number = number(values: values, monetary: true)
        let sign = text(values, negative ? "negative_sign" : "positive_sign", negative ? "-" : "")
        let before = integer(values, prefix + "_cs_precedes", 1) == 1
        let spacing = integer(values, prefix + "_sep_by_space", 0)
        let position = integer(values, prefix + "_sign_posn", 1)
        let gap = spacing == 1 && !symbol.isEmpty ? " " : ""
        var money = before ? symbol + gap + number : number + gap + symbol
        let signGap = spacing == 2 && !sign.isEmpty && !symbol.isEmpty ? " " : ""
        switch position {
        case 0: money = "(" + money + ")"
        case 2: money += (!before ? signGap : "") + sign
        case 3: money = before ? sign + signGap + symbol + gap + number : number + gap + sign + signGap + symbol
        case 4: money = before ? symbol + signGap + sign + gap + number : number + gap + symbol + signGap + sign
        default: money = sign + (before ? signGap : "") + money
        }
        return money
    }
    private static func text(_ values: [String: FieldValue], _ key: String, _ fallback: String) -> String {
        if case .text(let value) = values[key] { return value }; return fallback
    }
    private static func integer(_ values: [String: FieldValue], _ key: String, _ fallback: Int) -> Int {
        if case .integer(let value) = values[key] { return value }; return fallback
    }
}
