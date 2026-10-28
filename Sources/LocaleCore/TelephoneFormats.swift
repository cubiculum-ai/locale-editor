import Foundation

public struct TelephonePreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let format: String
    public let note: String
}

public enum TelephoneFormats {
    public static let international: [TelephonePreset] = [
        .init(id: "international-parentheses", name: "International: +country(area)number", format: "+%c(%a)%l", note: "Requested display layout; parentheses are punctuation, not part of a dial string"),
        .init(id: "international-compact", name: "International: +countryareanumber", format: "+%c%a%l", note: "Compact international form; use the area/national code without its domestic trunk prefix"),
        .init(id: "international-spaced", name: "International: +country area number", format: "+%c %a %l", note: "Human-readable international display with spaces"),
    ]

    /// Illustrative component substitution. LC_TELEPHONE describes a presentation convention,
    /// not a numbering-plan validator or a phone-number database.
    public static func render(_ format: String, country: String = "43", area: String = "1", domesticArea: String = "01", number: String = "5550123", extensionNumber: String = "", carrier: String = "") -> String {
        let replacements: [Character: String] = ["c": country, "a": area, "A": domesticArea, "l": number, "e": extensionNumber, "C": carrier, "%": "%"]
        let chars = Array(format)
        var result = "", i = 0, lastField = ""
        while i < chars.count {
            if chars[i] == "%", i + 1 < chars.count {
                i += 1
                if chars[i] == "t" { result += lastField.isEmpty ? "" : " " }
                else if let value = replacements[chars[i]] { result += value; lastField = value }
                else { result += "%" + String(chars[i]) }
            } else { result.append(chars[i]) }
            i += 1
        }
        return result
    }

    public static func sample(_ key: String, values: [String: FieldValue]) -> String {
        func text(_ key: String, _ fallback: String) -> String { if case .text(let value) = values[key] { return value }; return fallback }
        let country = text("int_prefix", "43")
        switch key {
        case "tel_int_fmt", "tel_dom_fmt":
            let area = country == "1" ? "202" : country == "44" ? "20" : "1"
            return render(text(key, key == "tel_int_fmt" ? "+%c(%a)%l" : "%A %l"), country: country.isEmpty ? "43" : country,
                          area: area, domesticArea: country == "1" ? area : "0" + area)
        case "int_prefix": return "+" + country + " …  (country calling code)"
        case "int_select": return text(key, "00") + " …  (outgoing international access prefix)"
        default: return ""
        }
    }
}
