import Foundation

public struct LocaleCatalog: Sendable {
    public let roots: [URL]
    public let names: [String]
    private let files: [String: URL]
    private let categories: [LocaleCategory: Set<String>]
    public var definitionNames: [String] { files.keys.sorted() }
    public func definitionNames(for category: LocaleCategory) -> Set<String> { categories[category, default: []] }

    public func effectiveValues(_ category: LocaleCategory, project: LocaleProject) throws -> [String: FieldValue] {
        let selection = try project.selection(category)
        let section = try resolve(selection.source, category: category)
        var result = selection.overrides
        for field in FieldSchema.fields(for: category) where result[field.key] == nil {
            if let entry = section.entry(field.key) { result[field.key] = try? field.decodeSource(entry.value, escape: section.escape) }
        }
        return result
    }

    /// The first root wins. Supplementary definitions remain addressable but are not shown as locales.
    public init(roots: [URL]) throws {
        self.roots = roots.map(\.standardizedFileURL)
        var files: [String: URL] = [:], names: [String] = [], categories: [LocaleCategory: Set<String>] = [:]
        let header = try NSRegularExpression(pattern: #"(?m)^(LC_[A-Z_]+)[ \t\r]*$"#)
        for root in self.roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                guard files[name] == nil, !name.hasPrefix("."), (try? LocaleProject.validateName(name)) != nil,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                files[name] = url
                // Lightweight indexing; full parsing is deferred until a section is selected.
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    for match in header.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                        if let range = Range(match.range(at: 1), in: text), let category = LocaleCategory(rawValue: String(text[range])) {
                            categories[category, default: []].insert(name)
                        }
                    }
                    if categories[.time, default: []].contains(name) { names.append(name) }
                }
            }
        }
        self.files = files
        self.categories = categories
        self.names = names.sorted()
        guard !names.isEmpty else {
            throw LocaleEditorError("No locale sources found. On Debian/Ubuntu install 'locales', or pass --sources /path/to/locales. On macOS try --sources Examples/locales --base demo_en.")
        }
    }

    public func source(_ name: String) throws -> LocaleSource {
        try LocaleProject.validateName(name)
        guard let url = files[name] else { throw LocaleEditorError("Missing locale source '\(name)' in \(roots.map(\.path).joined(separator: ", ")).") }
        return try LocaleSource.parse(String(contentsOf: url, encoding: .utf8), name: name)
    }

    public func resolve(_ name: String, category: LocaleCategory) throws -> SourceSection {
        try resolve(name, category: category, path: [])
    }
    private func resolve(_ name: String, category: LocaleCategory, path: [String]) throws -> SourceSection {
        guard !path.contains(name), path.count < 64 else {
            throw LocaleEditorError("Inheritance cycle or excessive depth in \(category.rawValue): \((path + [name]).joined(separator: " → "))")
        }
        guard let section = try source(name).sections[category] else { throw LocaleEditorError("\(name) has no \(category.rawValue) section.") }
        let copies = section.entries.filter { $0.keyword == "copy" }
        guard !copies.isEmpty else { return section }
        guard copies.count == 1 else { throw LocaleEditorError("Multiple copy statements in \(name)/\(category.rawValue).") }
        let parent = try SourceSyntax.unquote(copies[0].value, escape: section.escape)
        let inherited = try resolve(parent, category: category, path: path + [name])
        if section.entries.count == 1 { return inherited }
        if category == .collate || category == .ctype { return section } // localedef interprets tailoring
        throw LocaleEditorError("\(name)/\(category.rawValue) combines copy with local fields, which glibc does not support.")
    }

    public func inheritedValue(_ field: FieldDefinition, category: LocaleCategory, project: LocaleProject) throws -> FieldValue? {
        let section = try resolve(project.selection(category).source, category: category)
        guard let entry = section.entry(field.key) else { return nil }
        return try field.decodeSource(entry.value, escape: section.escape)
    }

    public func fingerprints(for project: LocaleProject) throws -> [String: String] {
        var result: [String: String] = [:]
        let regex = try NSRegularExpression(pattern: #"(?m)^\s*(?:copy|include)\s+"([^"]+)""#)
        func visit(_ name: String) throws {
            guard result[name] == nil else { return }
            guard let file = files[name] else { result[name] = "missing"; return }
            let data = try Data(contentsOf: file)
            // Stable change detector, not a security digest.
            let hash = data.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            result[name] = String(format: "fnv1a64:%016llx", hash)
            let text = String(decoding: data, as: UTF8.self)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { try visit(String(text[range])) }
            }
        }
        for selection in project.sections.values { try visit(selection.source) }
        return result
    }

    public func changedSources(for project: LocaleProject) throws -> [String] {
        guard !project.sourceFingerprints.isEmpty else { return [] }
        let current = try fingerprints(for: project)
        return Set(current.keys).union(project.sourceFingerprints.keys).filter {
            current[$0] != project.sourceFingerprints[$0]
        }.sorted()
    }
}
