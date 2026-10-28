import Foundation
import LocaleCore
import CLocaleBridge
#if os(Linux)
import Glibc
#endif

public struct BehaviorRequest: Codable {
    public var patterns: [String]
    public var responses: [String]
    public var characters: String
    public init(patterns: [String] = [], responses: [String] = ["yes", "Yes", "y", "ja", "J", "no", "No", "n", "nein", "1", "0", "+", "-", "maybe"], characters: String = "Aa Ää Öö Üü ß ẞ é Iıİi 09 ! 中") {
        self.patterns = patterns; self.responses = responses; self.characters = characters
    }
}
public struct BehaviorReport: Codable {
    // Escaped scalar keys distinguish canonically equivalent Unicode sequences:
    // POSIX regular expressions need not treat their UTF-8 representations alike.
    public var matches: [String: [String]]
    public var errors: [String: String]
    public var characters: [PreviewItem]
    public var uppercase: String
    public var lowercase: String
    public var transliteration: String
    public func matchedResponses(for pattern: String) -> [String] { matches[SourceSyntax.quote(pattern), default: []] }
    public func error(for pattern: String) -> String? { errors[SourceSyntax.quote(pattern)] }
    public func example(pattern: String) -> String {
        if let error = error(for: pattern) { return "Invalid POSIX expression: " + error }
        let samples = matchedResponses(for: pattern)
        return samples.isEmpty ? "Matches none of the sample responses" : "Matches: " + samples.map { $0.isEmpty ? "(empty)" : $0 }.joined(separator: " · ")
    }
}

extension LocaleRuntime {
    /// Uses the current locale only inside an isolated, compiled-locale worker.
    public static func runBehaviorWorker(_ request: BehaviorRequest) throws -> BehaviorReport {
        #if os(Linux)
        guard request.patterns.count <= 4096, request.responses.count <= 64, request.characters.unicodeScalars.count <= 256,
              (request.patterns + request.responses + [request.characters]).allSatisfy({ $0.utf8.count <= 4096 && !$0.utf8.contains(0) }),
              setlocale(LC_ALL, "") != nil else { throw LocaleEditorError("Invalid behavior request or unavailable locale.") }
        var report = BehaviorReport(matches: [:], errors: [:], characters: [], uppercase: "", lowercase: "", transliteration: "")
        var patterns: [String: String] = [:]
        for pattern in request.patterns { patterns[SourceSyntax.quote(pattern)] = pattern }
        func decode(_ bytes: [CChar]) -> String { String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        for (key, pattern) in patterns {
            report.matches[key] = []
            for response in request.responses.isEmpty ? [""] : request.responses {
                var error = [CChar](repeating: 0, count: 1024)
                let match = le_regex_match(pattern, response, &error, error.count)
                if match < 0 { report.errors[key] = decode(error); break }
                if match == 1 { report.matches[key, default: []].append(response) }
            }
        }
        for scalar in request.characters.unicodeScalars {
            let bits = le_character_classes(scalar.value)
            let labels: [(UInt32, String)] = [(1, "letter"), (2, "digit"), (4, "space"), (8, "punctuation"), (16, "uppercase"), (32, "lowercase"), (64, "printable"), (128, "control")]
            let upper = Unicode.Scalar(le_character_upper(scalar.value)).map(String.init) ?? String(scalar)
            let lower = Unicode.Scalar(le_character_lower(scalar.value)).map(String.init) ?? String(scalar)
            report.uppercase += upper; report.lowercase += lower
            let label = String(format: "U+%04X", scalar.value) + " " + (scalar == " " ? "SPACE" : String(scalar))
            report.characters.append(PreviewItem(label, labels.filter { bits & $0.0 != 0 }.map(\.1).joined(separator: ", ") + " · upper " + upper + " · lower " + lower))
        }
        var output = [CChar](repeating: 0, count: 16384)
        report.transliteration = le_transliterate(request.characters, &output, output.count) == 0 ? decode(output) : "Cannot transliterate these characters to ASCII with this profile"
        return report
        #else
        throw LocaleEditorError("Behavior examples require Linux/glibc.")
        #endif
    }
}
