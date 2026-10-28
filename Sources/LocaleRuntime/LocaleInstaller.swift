import Foundation
import LocaleCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct InstallManifest: Codable, Sendable {
    public let version: Int
    public let name: String
}

public struct InstallOutcome: Codable, Sendable {
    public let name: String
    public let scope: InstallScope
    public let destination: String
    public let selected: Bool
    public let selectionFiles: [String]
    public let backupDirectory: String
    public let activationScript: String?
}

/// A temporary, already-compiled package. Keep this object alive through the privilege handoff.
public final class PreparedLocaleInstall: Sendable {
    public let directory: URL
    public let name: String
    public init(project: LocaleProject, catalog: LocaleCatalog, worker: URL) throws {
        name = project.name
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("locale-editor-install-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try LocaleRuntime.compile(project, catalog: catalog, into: directory)
            try project.save(to: directory.appendingPathComponent("project.json"))
            try LocaleExporter.render(project, catalog: catalog).write(to: directory.appendingPathComponent("locale.src"), atomically: true, encoding: .utf8)
            try JSONEncoder().encode(InstallManifest(version: 1, name: project.name)).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            try LocaleInstaller.verify(name: name, root: directory, worker: worker)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

enum InstallFiles {
    static let categories = LocaleCategory.allCases.map { $0 == .messages ? "LC_MESSAGES/SYS_LC_MESSAGES" : $0.rawValue }

    /// openat + O_NOFOLLOW prevents a privileged helper from following package symlinks.
    static func read(_ root: URL, _ path: String, limit: Int = 64 * 1024 * 1024) throws -> Data {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw LocaleEditorError("Invalid package path.") }
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LocaleEditorError("Cannot safely open package directory: " + root.path) }
        defer { close(descriptor) }
        for part in components.dropLast() {
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw LocaleEditorError("Package directory is missing or is a symbolic link: " + path) }
            close(descriptor); descriptor = next
        }
        let file = openat(descriptor, components.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { throw LocaleEditorError("Package file is missing or is a symbolic link: " + path) }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(file, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size >= 0, info.st_size <= limit else {
            throw LocaleEditorError("Package contains an invalid or oversized file: " + path)
        }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, limit - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw LocaleEditorError("Package file exceeds its size limit.") }
        }
        return data
    }
}

public enum LocaleInstaller {
    private static let owner = "LinuxLocaleEditor/v1"
    private struct Receipt: Codable { let owner: String; let name: String; let scope: InstallScope }

    public static func manifest(at package: URL) throws -> InstallManifest {
        let result = try JSONDecoder().decode(InstallManifest.self, from: InstallFiles.read(package, "manifest.json", limit: 8192))
        guard result.version == 1 else { throw LocaleEditorError("Unsupported installation package version.") }
        try LocaleProject.validateName(result.name)
        guard !["c", "posix", "c.utf8"].contains(normalized(result.name)) else { throw LocaleEditorError("Use a distinct custom locale name; built-in locales cannot be replaced.") }
        return result
    }

    public static func checkDestination(name: String, locations: InstallLocations, replacing: Bool) throws -> Bool {
        try LocaleProject.validateName(name)
        let destination = locations.locales.appendingPathComponent(name)
        let exists = (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil
        if exists {
            let receipt: Receipt
            do { receipt = try JSONDecoder().decode(Receipt.self, from: InstallFiles.read(destination, ".locale-editor-install.json", limit: 8192)) }
            catch { throw LocaleEditorError("The destination already exists and is not an installation owned by this app. Choose another locale name.") }
            guard receipt.owner == owner, receipt.name == name else { throw LocaleEditorError("The existing locale is not owned by this app.") }
            if locations.isRealSystem {
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0 else { throw LocaleEditorError("The system locale directory has unexpected ownership.") }
            }
            guard replacing else { throw LocaleEditorError("This locale is already installed. Explicitly choose replacement to update it.") }
        }
        if locations.isRealSystem && FileManager.default.fileExists(atPath: "/usr/lib/locale/locale-archive") {
            let listing = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/localedef"), arguments: ["--list-archive"], environment: cleanEnvironment())
            guard listing.status == 0 else { throw LocaleEditorError("Cannot inspect the system locale archive: " + listing.output) }
            if listing.output.split(whereSeparator: \.isNewline).contains(where: { normalized(String($0)) == normalized(name) }) {
                throw LocaleEditorError("The system archive already contains this locale name. Use a new custom name to avoid shadowing it.")
            }
        }
        return exists
    }

    public static func install(package: URL, locations: InstallLocations, select: Bool, replacing: Bool, worker: URL) throws -> InstallOutcome {
        guard LocaleRuntime.supportsGlibc else { throw LocaleEditorError("Installation requires glibc Linux.") }
        if locations.isRealSystem && geteuid() != 0 { throw LocaleEditorError("System installation requires administrator privileges.") }
        let manifest = try manifest(at: package)
        let projectData = try InstallFiles.read(package, "project.json", limit: 2 * 1024 * 1024)
        let project = try JSONDecoder().decode(LocaleProject.self, from: projectData)
        try project.validate()
        guard project.name == manifest.name else { throw LocaleEditorError("Package name does not match its project.") }
        let sourceData = try InstallFiles.read(package, "locale.src", limit: 2 * 1024 * 1024)
        guard String(data: sourceData, encoding: .utf8) != nil else { throw LocaleEditorError("Package source is not UTF-8.") }
        var contents: [String: Data] = [:]
        var total = 0
        for category in InstallFiles.categories {
            let data = try InstallFiles.read(package, manifest.name + "/" + category)
            total += data.count
            guard total <= 256 * 1024 * 1024 else { throw LocaleEditorError("The locale package exceeds its size limit.") }
            contents[category] = data
        }
        let existed = try checkDestination(name: manifest.name, locations: locations, replacing: replacing)
        let writes = select ? try LocaleSelection.plan(name: manifest.name, locations: locations) : []
        let backup = locations.state.appendingPathComponent("backups/" + manifest.name + "/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: locations.locales, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let stage = locations.locales.appendingPathComponent(".locale-editor-stage-" + UUID().uuidString)
        let stagedLocale = stage.appendingPathComponent(manifest.name)
        try FileManager.default.createDirectory(at: stagedLocale, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: stage) }
        for (path, data) in contents {
            let url = stagedLocale.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try projectData.write(to: stagedLocale.appendingPathComponent("project.json"), options: .atomic)
        try sourceData.write(to: stagedLocale.appendingPathComponent("locale.src"), options: .atomic)
        try JSONEncoder().encode(Receipt(owner: owner, name: manifest.name, scope: locations.scope)).write(to: stagedLocale.appendingPathComponent(".locale-editor-install.json"), options: .atomic)
        for file in ["project.json", "locale.src", ".locale-editor-install.json"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stagedLocale.appendingPathComponent(file).path)
        }
        try verify(name: manifest.name, root: stage, worker: worker)
        let destination = locations.locales.appendingPathComponent(manifest.name)
        let previous = backup.appendingPathComponent("previous-locale")
        var movedOld = false, published = false
        do {
            if existed { try FileManager.default.moveItem(at: destination, to: previous); movedOld = true }
            try FileManager.default.moveItem(at: stagedLocale, to: destination); published = true
            // Verify the final lookup path before changing login defaults.
            try verify(name: manifest.name, root: locations.locales, worker: worker, defaultSearch: locations.isRealSystem)
            if select { try LocaleSelection.apply(writes, backup: backup.appendingPathComponent("selection")) }
        } catch {
            do {
                if published { try FileManager.default.removeItem(at: destination) }
                if movedOld { try FileManager.default.moveItem(at: previous, to: destination) }
            } catch { throw LocaleEditorError("Installation failed and the previous locale could not be restored automatically. Backups: \(backup.path). \(error.localizedDescription)") }
            throw error
        }
        return InstallOutcome(name: manifest.name, scope: locations.scope, destination: destination.path, selected: select,
                              selectionFiles: writes.map { $0.path.path }, backupDirectory: backup.path,
                              activationScript: select && locations.scope == .user ? locations.configuration.appendingPathComponent("linux-locale-editor/activate.sh").path : nil)
    }

    public static func verify(name: String, root: URL, worker: URL, defaultSearch: Bool = false) throws {
        let words = FileManager.default.temporaryDirectory.appendingPathComponent("locale-editor-verify-" + UUID().uuidString + ".json")
        try Data("[]".utf8).write(to: words, options: .atomic)
        defer { try? FileManager.default.removeItem(at: words) }
        var environment = cleanEnvironment()
        environment["LC_ALL"] = name
        if !defaultSearch { environment["LOCPATH"] = root.path }
        environment["LOCALE_EDITOR_VERIFY_ROOT"] = root.path
        environment["TZ"] = "UTC"
        let result = try ProcessRunner.run(worker, arguments: ["--preview-worker", words.path], environment: environment, timeout: 10)
        guard result.status == 0 else { throw LocaleEditorError("The installed locale could not be loaded: " + result.output) }
        let report = try JSONDecoder().decode(PreviewReport.self, from: Data(result.output.utf8))
        guard let loaded = report.localeName, normalized(loaded) == normalized(name) else {
            throw LocaleEditorError("glibc resolved a different locale name instead of the requested installation.")
        }
    }
    private static func normalized(_ name: String) -> String { name.lowercased().replacingOccurrences(of: "utf-8", with: "utf8") }
    private static func cleanEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where key.hasPrefix("LC_") || ["LANG", "LANGUAGE", "LOCPATH"].contains(key) { environment.removeValue(forKey: key) }
        environment["LANG"] = "C"
        return environment
    }
}
