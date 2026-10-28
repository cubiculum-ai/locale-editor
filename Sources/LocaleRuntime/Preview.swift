import Foundation
import LocaleCore
import CLocaleBridge
#if os(Linux)
import Glibc
#endif

public struct PreviewItem: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct PreviewReport: Codable, Sendable {
    public var engine: String
    public var items: [PreviewItem]
    public var sortedWords: [String]
    public var diagnostics: String
    public var localeName: String?
    public init(engine: String, items: [PreviewItem], sortedWords: [String], diagnostics: String = "", localeName: String? = nil) {
        self.engine = engine; self.items = items; self.sortedWords = sortedWords; self.diagnostics = diagnostics; self.localeName = localeName
    }
}

public enum LocaleRuntime {
    public static var currentExecutable: URL {
        #if os(Linux)
        URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
        #else
        Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        #endif
    }
    public static var supportsGlibc: Bool {
        #if os(Linux) && canImport(Glibc)
        true
        #else
        false
        #endif
    }

    public static func preview(_ project: LocaleProject, catalog: LocaleCatalog, worker: URL, words: [String] = ["zebra", "Örebro", "apple", "Ängel", "ångström", "Apple", "aachen", "ábaco", "ch", "cz"]) throws -> PreviewReport {
        guard supportsGlibc else {
            throw LocaleEditorError("Authoritative previews require Linux with glibc and localedef. Editing, saving and source export work on this host; run this project on Linux for previews.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locale-editor-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = try compile(project, catalog: catalog, into: root)
        let wordsURL = root.appendingPathComponent("words.json")
        try JSONEncoder().encode(words).write(to: wordsURL)
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where key.hasPrefix("LC_") || ["LANG", "LANGUAGE", "LOCPATH"].contains(key) { environment.removeValue(forKey: key) }
        environment["LOCPATH"] = root.path
        environment["LC_ALL"] = project.name
        environment["TZ"] = "UTC"
        let result = try ProcessRunner.run(worker, arguments: ["--preview-worker", wordsURL.path], environment: environment, timeout: 5)
        guard result.status == 0 else { throw LocaleEditorError("Preview worker failed:\n" + result.output) }
        var report = try JSONDecoder().decode(PreviewReport.self, from: Data(result.output.utf8))
        report.diagnostics = diagnostics
        return report
    }

    /// Writes only to the chosen directory; never updates the system locale archive.
    @discardableResult
    public static func compile(_ project: LocaleProject, catalog: LocaleCatalog, into root: URL) throws -> String {
        guard supportsGlibc else { throw LocaleEditorError("Compilation requires a glibc Linux host; export the source on this host instead.") }
        let source = try LocaleExporter.render(project, catalog: catalog)
        let executable = ["/usr/bin/localedef", "/bin/localedef"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let executable else { throw LocaleEditorError("localedef is missing. Install the distribution's locale tools and source data.") }
        let version = try ProcessRunner.run(URL(fileURLWithPath: executable), arguments: ["--version"])
        guard version.status == 0, version.output.contains("GLIBC") || version.output.contains("GNU libc") else {
            throw LocaleEditorError("This backend requires GNU glibc localedef.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(project.name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LocaleEditorError("\(destination.path) already exists. Choose a fresh output directory.")
        }
        let sourceURL = root.appendingPathComponent(".source-" + UUID().uuidString)
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["I18NPATH"] = catalog.roots.map(\.path).joined(separator: ":")
        do {
            // Building the full Unicode/collation tables can exceed 20 seconds on a Pi.
            // Keep compilation bounded independently of the much shorter preview workers.
            let result = try ProcessRunner.run(URL(fileURLWithPath: executable), arguments: ["--no-archive", "-f", "UTF-8", "-i", sourceURL.path, destination.path], environment: environment, timeout: 120)
            // Warnings are surfaced and are not silently forced through with -c.
            guard result.status == 0 else { throw LocaleEditorError("localedef exited \(result.status):\n\(result.output)") }
            return result.output
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Invoke only in a dedicated child process: setlocale is process-global and libc caches locale data.
    public static func runPreviewWorker(words: [String]) throws -> PreviewReport {
        #if os(Linux) && canImport(Glibc)
        guard let loaded = setlocale(LC_ALL, "") else { throw LocaleEditorError("glibc could not load the requested compiled locale.") }
        let loadedName = String(cString: loaded)
        if let root = ProcessInfo.processInfo.environment["LOCALE_EDITOR_VERIFY_ROOT"], let requested = ProcessInfo.processInfo.environment["LC_ALL"] {
            try verifyMappedLocale(root: URL(fileURLWithPath: root), name: requested)
        }
        var items: [PreviewItem] = []
        for (year, month, day, hour) in [(2026, 10, 27, 17), (2000, 2, 29, 0), (2027, 1, 1, 12)] {
            var date = tm()
            date.tm_year = Int32(year - 1900); date.tm_mon = Int32(month - 1); date.tm_mday = Int32(day)
            date.tm_hour = Int32(hour); date.tm_min = 4; date.tm_sec = 5
            _ = timegm(&date)
            for (label, format) in [("Date", "%x"), ("Time", "%X"), ("Combined", "%c"), ("12-hour", "%r")] {
                var buffer = [CChar](repeating: 0, count: 8192)
                let count = strftime(&buffer, buffer.count, format, &date)
                let value = count > 0 ? decode(buffer, count: count) : "(empty or exceeds preview buffer)"
                items.append(PreviewItem("\(year)-\(month)-\(day) \(label)", value))
            }
        }
        for number in [1234567.89, -1234.5, 0] {
            var buffer = [CChar](repeating: 0, count: 8192)
            let n = le_format_number(&buffer, buffer.count, number)
            guard n >= 0 && n < buffer.count else { throw LocaleEditorError("Number preview exceeded its buffer.") }
            items.append(PreviewItem("Number \(number)", decode(buffer, count: Int(n))))
            let m = le_format_money(&buffer, buffer.count, number)
            guard m >= 0 && m < buffer.count else { throw LocaleEditorError("Currency preview failed or exceeded its buffer.") }
            items.append(PreviewItem("Currency \(number)", decode(buffer, count: Int(m))))
            let international = le_format_international_money(&buffer, buffer.count, number)
            guard international >= 0 && international < buffer.count else { throw LocaleEditorError("International currency preview failed.") }
            items.append(PreviewItem("International currency \(number)", decode(buffer, count: Int(international))))
        }
        // Tie-break by original position so collation-equivalent words retain input order.
        let sorted = words.enumerated().sorted { a, b in
            let comparison = a.element.withCString { lhs in b.element.withCString { rhs in strcoll(lhs, rhs) } }
            return comparison == 0 ? a.offset < b.offset : comparison < 0
        }.map(\.element)
        let query = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/locale"), arguments: ["-k", "LC_PAPER", "LC_MEASUREMENT", "LC_TIME", "LC_TELEPHONE", "LC_ADDRESS", "LC_IDENTIFICATION", "LC_NAME", "LC_MESSAGES"])
        guard query.status == 0 else { throw LocaleEditorError("Could not read compiled locale settings: " + query.output) }
        let settings = ["height": "Paper height (mm)", "width": "Paper width (mm)",
                        "measurement": "Measurement (1 metric, 2 US)", "first_weekday": "First weekday (offset from week base)",
                        "first_workday": "First workday (offset from week base)", "week-1stday": "Week base", "date_fmt": "GNU date format",
                        "tel_int_fmt": "International telephone format", "tel_dom_fmt": "Domestic telephone format",
                        "int_prefix": "Country calling code", "int_select": "International access prefix",
                        "postal_fmt": "Postal address format", "title": "Metadata title", "revision": "Metadata revision", "date": "Metadata date",
                        "name_fmt": "Name format", "yesexpr": "Yes expression", "noexpr": "No expression", "yesstr": "Yes label", "nostr": "No label", "week-1stweek": "Minimum days in week 1"]
        for line in query.output.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, let label = settings[parts[0]] { items.append(PreviewItem(label, parts[1])) }
        }
        return PreviewReport(engine: "glibc: strftime, snprintf, strfmon, strcoll (UTC samples)", items: items, sortedWords: sorted, localeName: loadedName)
        #else
        throw LocaleEditorError("Preview worker requires glibc Linux.")
        #endif
    }

    private static func decode(_ buffer: [CChar], count: Int) -> String {
        String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// setlocale may retain a requested name even when it falls back. On glibc Linux,
    /// verify the device/inode identities of every mapped category, without exposing maps.
    private static func verifyMappedLocale(root: URL, name: String) throws {
        #if os(Linux)
        try LocaleProject.validateName(name)
        // procfs reports a zero file size; read its stream instead of using a size-based load.
        let stream = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/proc/self/maps"))
        defer { try? stream.close() }
        let mappings = String(decoding: try stream.readToEnd() ?? Data(), as: UTF8.self)
        var identities: Set<String> = []
        for line in mappings.split(separator: "\n") {
            let fields = line.split(maxSplits: 5, whereSeparator: \.isWhitespace)
            guard fields.count >= 5 else { continue }
            let device = fields[3].split(separator: ":")
            if device.count == 2, let major = UInt32(device[0], radix: 16), let minor = UInt32(device[1], radix: 16), let inode = UInt64(fields[4]) {
                identities.insert("\(major):\(minor):\(inode)")
            }
        }
        for category in InstallFiles.categories {
            var major: UInt32 = 0, minor: UInt32 = 0, inode: UInt64 = 0
            let path = root.appendingPathComponent(name).appendingPathComponent(category).path
            guard le_file_identity(path, &major, &minor, &inode) == 0, identities.contains("\(major):\(minor):\(inode)") else {
                throw LocaleEditorError("glibc did not load the installed \(category) file; a locale alias or fallback may be taking precedence.")
            }
        }
        #endif
    }
}

public enum TerminalGeometry {
    public static var columns: Int { Int(le_terminal_columns()) }
    public static var rows: Int { Int(le_terminal_rows()) }
}
