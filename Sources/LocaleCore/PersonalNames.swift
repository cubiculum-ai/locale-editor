import Foundation

/// Illustrative LC_NAME substitution. Applications supply the person's actual components.
public enum PersonalNames {
    public static func render(_ format: String, fields: [Character: String]) -> String {
        let chars = Array(format)
        var result = "", previous = "", i = 0
        while i < chars.count {
            if chars[i] == "%", i + 1 < chars.count {
                i += 1
                if chars[i] == "t" { result += previous.isEmpty ? "" : " " }
                else if chars[i] == "%" { result += "%" }
                else if let text = fields[chars[i]] { result += text; previous = text }
                else { result += "%" + String(chars[i]) }
            } else { result.append(chars[i]) }
            i += 1
        }
        return result
    }

    public static func sample(_ key: String, values: [String: FieldValue]) -> String {
        func text(_ key: String, _ fallback: String = "") -> String { if case .text(let s) = values[key] { return s }; return fallback }
        let salutation = text(key == "name_fmt" ? "name_gen" : key, text("name_mr"))
        let fields: [Character: String] = ["g": "Alex", "G": "A.", "l": "Alex", "o": "Alex",
            "m": "Robin", "M": "R.", "f": "Example", "F": "EXAMPLE", "p": "Engineer",
            "s": "Doctor", "S": "Dr.", "d": salutation]
        return render(text("name_fmt", "%g%t%m%t%f"), fields: fields)
    }
}
