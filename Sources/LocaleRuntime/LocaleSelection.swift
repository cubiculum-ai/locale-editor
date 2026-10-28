import Foundation
import LocaleCore

public enum InstallScope: String, Codable, Sendable { case user, system }

public struct InstallLocations: Sendable {
    public let scope: InstallScope
    public let locales: URL
    public let state: URL
    public let configuration: URL
    public let profiles: [URL]
    public let systemConfigurations: [URL]
    public let isRealSystem: Bool

    public static func user(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        func directory(_ variable: String, fallback: URL) -> URL {
            guard let path = environment[variable], path.hasPrefix("/") else { return fallback }
            return URL(fileURLWithPath: path)
        }
        let data = directory("XDG_DATA_HOME", fallback: home.appendingPathComponent(".local/share"))
        let config = directory("XDG_CONFIG_HOME", fallback: home.appendingPathComponent(".config"))
        let shell = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/sh").lastPathComponent
        var profiles: [URL] = []
        if ["bash", "zsh", "sh", "dash"].contains(shell) { profiles.append(home.appendingPathComponent(".profile")) }
        if shell == "bash" {
            profiles.append(home.appendingPathComponent(".bashrc"))
            for name in [".bash_profile", ".bash_login"] where FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path) {
                profiles.append(home.appendingPathComponent(name)); break
            }
        }
        if shell == "zsh" {
            let zdot = directory("ZDOTDIR", fallback: home)
            profiles += [zdot.appendingPathComponent(".zprofile"), zdot.appendingPathComponent(".zshrc")]
        }
        return Self(scope: .user, locales: data.appendingPathComponent("linux-locale-editor/locales"), state: data.appendingPathComponent("linux-locale-editor"),
                    configuration: config, profiles: profiles, systemConfigurations: [], isRealSystem: false)
    }

    /// A non-root prefix is useful for testing system layouts without touching host settings.
    public static func system(root: URL = URL(fileURLWithPath: "/")) -> Self {
        let root = root.standardizedFileURL
        let candidates = [root.appendingPathComponent("etc/locale.conf"), root.appendingPathComponent("etc/default/locale")]
        var configs = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }.map { $0.resolvingSymlinksInPath() }
        if configs.isEmpty { configs = [candidates[0]] }
        var seen: Set<String> = []
        configs = configs.filter { seen.insert($0.path).inserted }
        return Self(scope: .system, locales: root.appendingPathComponent("usr/lib/locale"), state: root.appendingPathComponent("var/lib/linux-locale-editor"),
                    configuration: root.appendingPathComponent("etc"), profiles: [], systemConfigurations: configs, isRealSystem: root.path == "/")
    }
}

public struct SelectionWrite: Sendable {
    public let path: URL
    public let data: Data
}

public enum LocaleSelection {
    public static let markerStart = "# >>> Linux Locale Editor >>>"
    public static let markerEnd = "# <<< Linux Locale Editor <<<"
    public static let overrides = ["LC_ALL", "LANGUAGE"] + LocaleCategory.allCases.map(\.rawValue)
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public static func profile(_ original: String, activation: URL) throws -> String {
        let block = markerStart + "\n[ ! -r " + quote(activation.path) + " ] || . " + quote(activation.path) + "\n" + markerEnd
        let starts = original.components(separatedBy: markerStart).count - 1
        let ends = original.components(separatedBy: markerEnd).count - 1
        if starts == 0 && ends == 0 { return original + (original.isEmpty || original.hasSuffix("\n") ? "" : "\n") + block + "\n" }
        guard starts == 1, ends == 1, let start = original.range(of: markerStart), let end = original.range(of: markerEnd), start.lowerBound < end.lowerBound else {
            throw LocaleEditorError("A shell profile contains an incomplete or duplicate Locale Editor block. No selection files were changed.")
        }
        return String(original[..<start.lowerBound]) + block + String(original[end.upperBound...])
    }

    public static func systemConfiguration(_ original: String, name: String) -> String {
        let keys = Set(overrides + ["LANG"])
        let kept = original.components(separatedBy: "\n").filter { line in
            let key = line.split(separator: "=", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return !keys.contains(key) && line != "# Selected by Linux Locale Editor"
        }.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return (kept.isEmpty ? "" : kept + "\n") + "# Selected by Linux Locale Editor\nLANG=" + name + "\n"
    }

    public static func plan(name: String, locations: InstallLocations) throws -> [SelectionWrite] {
        try LocaleProject.validateName(name)
        if locations.scope == .system {
            return try locations.systemConfigurations.map { url in
                let original = FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
                return SelectionWrite(path: url, data: Data(systemConfiguration(original, name: name).utf8))
            }
        }
        let activation = locations.configuration.appendingPathComponent("linux-locale-editor/activate.sh")
        let envFile = locations.configuration.appendingPathComponent("environment.d/90-linux-locale-editor.conf")
        for path in [activation.path, envFile.path, locations.locales.path] + locations.profiles.map(\.path) {
            guard !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw LocaleEditorError("Activation paths cannot contain control characters.") }
        }
        let script = "# Generated by Linux Locale Editor. Source this file to activate in this shell.\n" +
            "export LANG=" + quote(name) + "\nexport LOCPATH=" + quote(locations.locales.path) + "\nunset " + overrides.joined(separator: " ") + "\n"
        func environmentValue(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "$", with: "$$") + "\""
        }
        let environment = "# Selected by Linux Locale Editor; applies to future systemd user services.\nLANG=" + name + "\nLOCPATH=" + environmentValue(locations.locales.path) + "\n" + overrides.map { $0 + "=" }.joined(separator: "\n") + "\n"
        var writes = [SelectionWrite(path: activation, data: Data(script.utf8)), SelectionWrite(path: envFile, data: Data(environment.utf8))]
        for profileURL in locations.profiles {
            let original = FileManager.default.fileExists(atPath: profileURL.path) ? try String(contentsOf: profileURL, encoding: .utf8) : ""
            writes.append(SelectionWrite(path: profileURL, data: Data(try profile(original, activation: activation).utf8)))
        }
        return writes
    }

    /// Back up every original before the first write; restore already-written files on failure.
    public static func apply(_ writes: [SelectionWrite], backup: URL) throws {
        struct Original { let url: URL; let data: Data?; let mode: NSNumber? }
        var originals: [Original] = []
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (index, write) in writes.enumerated() {
            let exists = (try? FileManager.default.attributesOfItem(atPath: write.path.path)) != nil
            let actual = exists ? write.path.resolvingSymlinksInPath() : write.path
            let old = exists ? try Data(contentsOf: actual) : nil
            let mode = (try? FileManager.default.attributesOfItem(atPath: actual.path)[.posixPermissions]) as? NSNumber
            originals.append(Original(url: actual, data: old, mode: mode))
            if let old { try old.write(to: backup.appendingPathComponent("\(index).original"), options: .atomic) }
        }
        let record = originals.enumerated().map { ["path": $0.element.url.path, "backup": $0.element.data == nil ? "(did not exist)" : "\($0.offset).original"] }
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: backup.appendingPathComponent("selection-backups.json"), options: .atomic)
        var completed = 0
        do {
            for (index, write) in writes.enumerated() {
                let original = originals[index]
                try FileManager.default.createDirectory(at: original.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try write.data.write(to: original.url, options: .atomic)
                completed = index + 1
                try FileManager.default.setAttributes([.posixPermissions: original.mode ?? NSNumber(value: 0o644)], ofItemAtPath: original.url.path)
            }
        } catch {
            var failures: [String] = []
            for original in originals.prefix(completed).reversed() {
                do {
                    if let old = original.data {
                        try old.write(to: original.url, options: .atomic)
                        if let mode = original.mode { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: original.url.path) }
                    } else { try FileManager.default.removeItem(at: original.url) }
                } catch { failures.append(original.url.path + ": " + error.localizedDescription) }
            }
            if !failures.isEmpty { throw LocaleEditorError("Selection failed and some files could not be restored. Backups: \(backup.path)\n" + failures.joined(separator: "\n")) }
            throw error
        }
    }
}
