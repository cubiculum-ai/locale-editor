import Foundation

public struct LocalePreset: Sendable, Identifiable {
    public let value: FieldValue
    public let sources: [String]
    public var id: String { value.source }
}

/// A snapshot of distinct semantic values, including inherited definitions. Shared by all frontends.
/// Exact serialized Unicode scalars are used as keys, so visually similar but different symbols remain distinct.
public struct LocalePresetIndex {
    private var values: [String: [LocalePreset]] = [:]
    public private(set) var diagnostics: [String] = []

    public init(catalog: LocaleCatalog) {
        var documents: [String: LocaleSource] = [:]
        for name in catalog.definitionNames {
            do { documents[name] = try catalog.source(name) }
            catch { diagnostics.append("\(name): \(error.localizedDescription)") }
        }
        var resolved: [String: SourceSection] = [:]
        func resolve(_ name: String, _ category: LocaleCategory, _ path: Set<String> = []) throws -> SourceSection {
            let key = name + ":" + category.rawValue
            if let cached = resolved[key] { return cached }
            guard !path.contains(name), path.count < 64 else { throw LocaleEditorError("Inheritance cycle: \(name)") }
            guard let section = documents[name]?.sections[category] else { throw LocaleEditorError("Missing \(name)/\(category.rawValue)") }
            if let copy = section.entry("copy"), section.entries.count == 1 {
                let result = try resolve(SourceSyntax.unquote(copy.value, escape: section.escape), category, path.union([name]))
                resolved[key] = result
                return result
            }
            resolved[key] = section
            return section
        }
        for category in LocaleCategory.allCases where !FieldSchema.fields(for: category).isEmpty {
            var byField: [String: [String: (FieldValue, Set<String>)]] = [:]
            for name in catalog.definitionNames where documents[name]?.sections[category] != nil {
                do {
                    let section = try resolve(name, category)
                    for field in FieldSchema.fields(for: category) {
                        guard let entry = section.entry(field.key) else { continue }
                        do {
                            let value = try field.decodeSource(entry.value, escape: section.escape)
                            try field.validate(value)
                            var found = byField[field.key, default: [:]][value.source] ?? (value, [])
                            found.1.insert(name)
                            byField[field.key, default: [:]][value.source] = found
                        } catch { diagnostics.append("\(name)/\(field.key): \(error.localizedDescription)") }
                    }
                } catch { diagnostics.append(error.localizedDescription) }
            }
            for (field, definitions) in byField {
                values[category.rawValue + ":" + field] = definitions.values.map {
                    LocalePreset(value: $0.0, sources: $0.1.sorted())
                }.sorted { $0.value.source < $1.value.source }
            }
        }
    }

    public func presets(for category: LocaleCategory, field: String) -> [LocalePreset] {
        values[category.rawValue + ":" + field] ?? []
    }
}
