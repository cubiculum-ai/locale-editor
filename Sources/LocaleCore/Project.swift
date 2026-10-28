import Foundation

public struct LocaleEditorError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum LocaleCategory: String, Codable, CaseIterable, Sendable {
    case time = "LC_TIME", numeric = "LC_NUMERIC", monetary = "LC_MONETARY"
    case paper = "LC_PAPER", measurement = "LC_MEASUREMENT"
    case messages = "LC_MESSAGES", address = "LC_ADDRESS", name = "LC_NAME"
    case telephone = "LC_TELEPHONE", collate = "LC_COLLATE", ctype = "LC_CTYPE"
    case identification = "LC_IDENTIFICATION"

    public var title: String {
        switch self {
        case .time: "Date and time"
        case .numeric: "Numbers"
        case .monetary: "Currency"
        case .paper: "Paper"
        case .measurement: "Measurement"
        case .messages: "Yes / no responses"
        case .address: "Address"
        case .name: "Names"
        case .telephone: "Telephone"
        case .collate: "Sorting"
        case .ctype: "Character handling"
        case .identification: "Metadata"
        }
    }
}

/// Values are semantic, not localedef syntax. The exporter alone performs quoting.
public enum FieldValue: Codable, Equatable, Sendable {
    case text(String)
    case integer(Int)
    case integers([Int])
    case strings([String])

    public var display: String {
        switch self {
        case .text(let s): s
        case .integer(let n): String(n)
        case .integers(let ns): ns.map(String.init).joined(separator: ";")
        case .strings(let ss): ss.joined(separator: " | ")
        }
    }

    public var source: String {
        switch self {
        case .text(let s): SourceSyntax.quote(s)
        case .integer(let n): String(n)
        case .integers(let ns): ns.map(String.init).joined(separator: ";")
        case .strings(let ss): ss.map(SourceSyntax.quote).joined(separator: ";")
        }
    }
}

public struct CategorySelection: Codable, Equatable, Sendable {
    public var source: String
    public var overrides: [String: FieldValue]
    public init(source: String, overrides: [String: FieldValue] = [:]) {
        self.source = source
        self.overrides = overrides
    }
}

public struct LocaleProject: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var name: String
    // String keys keep project JSON straightforward for external tools.
    public var sections: [String: CategorySelection]
    public var sourceFingerprints: [String: String] = [:]

    public init(name: String, base: String) throws {
        try Self.validateName(name)
        self.name = name
        sections = Dictionary(uniqueKeysWithValues: LocaleCategory.allCases.map {
            ($0.rawValue, CategorySelection(source: base))
        })
    }

    public static func validateName(_ name: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.@")
        guard !name.isEmpty, name.count <= 120, name != ".", name != "..",
              name.first?.isLetter == true,
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw LocaleEditorError("Use a locale name such as en_GB.UTF-8@personal (letters, digits, _, -, ., @).")
        }
    }

    public func selection(_ category: LocaleCategory) throws -> CategorySelection {
        guard let selection = sections[category.rawValue] else {
            throw LocaleEditorError("Project is missing \(category.rawValue).")
        }
        return selection
    }

    public func validate() throws {
        guard version == 1 else { throw LocaleEditorError("Unsupported project version \(version).") }
        try Self.validateName(name)
        guard Set(sections.keys) == Set(LocaleCategory.allCases.map(\.rawValue)) else {
            throw LocaleEditorError("Project must contain exactly the supported locale categories.")
        }
        for category in LocaleCategory.allCases {
            let selection = try selection(category)
            try Self.validateName(selection.source)
            for (key, value) in selection.overrides {
                guard let field = FieldSchema.field(category, key) else {
                    throw LocaleEditorError("Unsupported override: \(category.rawValue).\(key)")
                }
                try field.validate(value)
            }
        }
    }

    public static func load(from url: URL) throws -> Self {
        let project = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try project.validate()
        return project
    }

    public func save(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Presentation-independent editing, including history. Frontends own focus and layout only.
public struct EditorSession {
    public private(set) var project: LocaleProject
    private var undoStack: [LocaleProject] = []
    private var redoStack: [LocaleProject] = []
    private var savedProject: LocaleProject

    public init(project: LocaleProject) {
        self.project = project
        savedProject = project
    }
    public var isDirty: Bool { project != savedProject }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    private mutating func change(_ body: (inout LocaleProject) throws -> Void) throws {
        var next = project
        try body(&next)
        try next.validate()
        guard next != project else { return }
        undoStack.append(project)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        project = next
    }

    /// Overrides are deliberately retained when changing a parent; reset is a separate operation.
    public mutating func inherit(_ category: LocaleCategory, from source: String, catalog: LocaleCatalog) throws {
        _ = try catalog.resolve(source, category: category)
        try change { $0.sections[category.rawValue]?.source = source }
    }
    public mutating func set(_ category: LocaleCategory, key: String, value: FieldValue) throws {
        try set(category, values: [key: value])
    }
    public mutating func set(_ category: LocaleCategory, values: [String: FieldValue]) throws {
        try set([category: values])
    }
    /// Apply a convention across categories as one undoable edit.
    public mutating func set(_ changes: [LocaleCategory: [String: FieldValue]]) throws {
        try change { project in
            for (category, values) in changes {
                for (key, value) in values { project.sections[category.rawValue]?.overrides[key] = value }
            }
        }
    }
    public mutating func reset(_ category: LocaleCategory, key: String) throws {
        try reset(category, keys: [key])
    }
    public mutating func reset(_ category: LocaleCategory, keys: [String]) throws {
        try change { project in
            for key in keys { project.sections[category.rawValue]?.overrides.removeValue(forKey: key) }
        }
    }
    public mutating func rename(_ name: String) throws { try change { $0.name = name } }
    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project); project = previous
    }
    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next
    }
    public mutating func save(to url: URL, catalog: LocaleCatalog) throws {
        var next = project
        next.sourceFingerprints = try catalog.fingerprints(for: project)
        try next.save(to: url)
        project = next
        savedProject = next
    }
}
