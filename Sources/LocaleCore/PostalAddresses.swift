import Foundation

public struct PostalAddressSample: Sendable {
    public var fields: [Character: String]
    public var romanized: [Character: String]
    public init(fields: [Character: String] = ["n": "Alex Example", "a": "", "f": "Example Company", "d": "", "b": "", "s": "Example Street", "h": "12", "r": "Suite 4", "e": "Floor 2", "l": "", "z": "12345", "T": "Sample City", "S": "Example Region", "c": "Example Country", "C": "EX"], romanized: [Character: String] = [:]) {
        self.fields = fields; self.romanized = romanized
    }
}

public enum PostalAddresses {
    /// LC_ADDRESS descriptor expansion, including conditional spacing/newlines and %R variants.
    /// These are illustrative mailing-label components, not a postal-address validator.
    public static func render(_ format: String, sample: PostalAddressSample = PostalAddressSample()) -> String {
        let characters = Array(format)
        var output = "", previous = "", index = 0
        while index < characters.count {
            guard characters[index] == "%", index + 1 < characters.count else { output.append(characters[index]); index += 1; continue }
            index += 1
            var romanized = false
            if characters[index] == "R", index + 1 < characters.count { romanized = true; index += 1 }
            let key = characters[index]
            switch key {
            case "N": if !previous.isEmpty { output += "\n" }
            case "t": if !previous.isEmpty { output += " " }
            case "%": output += "%"
            default:
                if let value = (romanized ? sample.romanized[key] : nil) ?? sample.fields[key] { output += value; previous = value }
                else { output += "%" + (romanized ? "R" : "") + String(key) }
            }
            index += 1
        }
        return output
    }

    public static func lines(values: [String: FieldValue]) -> [String] {
        guard case .text(let format) = values["postal_fmt"] else { return ["(no postal format specified)"] }
        var sample = PostalAddressSample()
        if case .text(let country) = values["country_name"], !country.isEmpty { sample.fields["c"] = country }
        if case .text(let country) = values["country_post"], !country.isEmpty { sample.fields["C"] = country }
        let result = render(format, sample: sample).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return result.isEmpty ? ["(empty address layout)"] : result
    }
}
