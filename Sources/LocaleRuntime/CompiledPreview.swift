import Foundation
import LocaleCore
#if os(Linux)
import Glibc
#endif

/// Compiles once per editor state. Batch formatting keeps a popup with hundreds of formats fast.
/// This owns its private directory; callers never mutate the locale of their UI process.
public final class CompiledPreview: Sendable {
    private let root: URL
    private let worker: URL
    private let environment: [String: String]
    public let diagnostics: String

    public init(project: LocaleProject, catalog: LocaleCatalog, worker: URL) throws {
        guard LocaleRuntime.supportsGlibc else { throw LocaleEditorError("Formatted examples require Linux/glibc.") }
        self.worker = worker
        root = FileManager.default.temporaryDirectory.appendingPathComponent("locale-editor-live-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do { diagnostics = try LocaleRuntime.compile(project, catalog: catalog, into: root) }
        catch { try? FileManager.default.removeItem(at: root); throw error }
        var env = ProcessInfo.processInfo.environment
        for key in Array(env.keys) where key.hasPrefix("LC_") || ["LANG", "LANGUAGE", "LOCPATH"].contains(key) { env.removeValue(forKey: key) }
        env["LOCPATH"] = root.path; env["LC_ALL"] = project.name; env["TZ"] = "UTC"
        environment = env
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    public func report(words: [String]) throws -> PreviewReport {
        let result: PreviewReport = try request(words, flag: "--preview-worker")
        return PreviewReport(engine: result.engine, items: result.items, sortedWords: result.sortedWords, diagnostics: diagnostics, localeName: result.localeName)
    }
    public func formatExamples(_ formats: [String], gnuDate: Bool = false) throws -> [String: String] {
        try request(Array(Set(formats)).sorted(), flag: gnuDate ? "--date-format-worker" : "--format-worker")
    }
    public func behaviorExamples(_ request: BehaviorRequest) throws -> BehaviorReport {
        try self.request(request, flag: "--behavior-worker")
    }
    private func request<Input: Encodable, Output: Decodable>(_ value: Input, flag: String) throws -> Output {
        let url = root.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(value).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try ProcessRunner.run(worker, arguments: [flag, url.path], environment: environment, timeout: 5)
        guard result.status == 0 else { throw LocaleEditorError("Example worker failed: " + result.output) }
        return try JSONDecoder().decode(Output.self, from: Data(result.output.utf8))
    }
}

extension LocaleRuntime {
    public static func runDateFormatWorker(formats: [String]) throws -> [String: String] {
        guard supportsGlibc, formats.count <= 4096,
              formats.allSatisfy({ $0.utf8.count <= 4096 && !$0.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 31 }) }) else {
            throw LocaleEditorError("Invalid GNU date format request.")
        }
        guard !formats.isEmpty else { return [:] }
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/date"), arguments: ["-u", "--date=2026-10-27 17:04:05 UTC", "+" + formats.joined(separator: "\u{1F}")])
        guard result.status == 0 else { throw LocaleEditorError(result.output) }
        var output = result.output
        if output.last == "\n" { output.removeLast() }
        let samples = output.components(separatedBy: "\u{1F}")
        guard samples.count == formats.count else { throw LocaleEditorError("GNU date returned an unexpected example count.") }
        return Dictionary(zip(formats, samples.map { $0.isEmpty ? "(empty)" : $0 }), uniquingKeysWith: { _, latest in latest })
    }
    public static func runFormatWorker(formats: [String]) throws -> [String: String] {
        #if os(Linux) && canImport(Glibc)
        guard formats.count <= 4096, formats.allSatisfy({ $0.utf8.count <= 4096 && !$0.utf8.contains(0) }),
              setlocale(LC_ALL, "") != nil else { throw LocaleEditorError("Invalid format request or unavailable locale.") }
        var date = tm()
        date.tm_year = 126; date.tm_mon = 9; date.tm_mday = 27; date.tm_hour = 17; date.tm_min = 4; date.tm_sec = 5
        _ = timegm(&date)
        var results: [String: String] = [:]
        for format in formats {
            if format.isEmpty { results[format] = "(empty)"; continue }
            var buffer = [CChar](repeating: 0, count: 16384)
            let count = strftime(&buffer, buffer.count, format, &date)
            results[format] = count > 0 ? String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self) : "(empty or too long)"
        }
        return results
        #else
        throw LocaleEditorError("Formatted examples require Linux/glibc.")
        #endif
    }
}
