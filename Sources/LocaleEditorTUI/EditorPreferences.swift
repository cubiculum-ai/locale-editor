import Foundation
import LocaleCore

enum CursorMode: String, Codable { case standard, legacy }
struct EditorPreferences: Codable {
    var cursorMode: CursorMode = .standard
    static var url: URL {
        let root = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return root.appendingPathComponent("linux-locale-editor/preferences.json")
    }
    static func load() -> Self {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
