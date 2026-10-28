import Foundation
import XCTest
import LocaleCore
@testable import LocaleRuntime

final class LocaleInstallerTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("locale-install-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func locations() -> InstallLocations {
        .user(home: root.appendingPathComponent("home"), environment: ["SHELL": "/bin/zsh", "XDG_CONFIG_HOME": root.appendingPathComponent("config").path, "XDG_DATA_HOME": root.appendingPathComponent("share").path])
    }
    private func native() throws -> (LocaleCatalog, URL, LocaleProject) {
        guard LocaleRuntime.supportsGlibc else { throw XCTSkip("Requires Linux/glibc.") }
        let source = URL(fileURLWithPath: "/usr/share/i18n/locales")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("en_GB").path) else { throw XCTSkip("Requires locale sources.") }
        let binary = ProcessInfo.processInfo.environment["LOCALE_EDITOR_BINARY"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/locale-editor")
        return (try LocaleCatalog(roots: [source]), binary, try LocaleProject(name: "en_GB.UTF-8@install_test-" + UUID().uuidString.lowercased(), base: "en_GB"))
    }

    func testManagedProfileBlockPreservesContentAndIsIdempotent() throws {
        let script = root.appendingPathComponent("a'b/activate.sh")
        let original = "# user's settings\nexport EDITOR=vi\n"
        let first = try LocaleSelection.profile(original, activation: script)
        XCTAssertTrue(first.hasPrefix(original))
        XCTAssertEqual(try LocaleSelection.profile(first, activation: script), first)
        XCTAssertTrue(first.contains("'\\''"))
        XCTAssertThrowsError(try LocaleSelection.profile(LocaleSelection.markerStart, activation: script))
        XCTAssertThrowsError(try LocaleSelection.profile(first + first, activation: script))
    }

    func testSelectionWriteFailureRollsBackAlreadyWrittenFiles() throws {
        let first = root.appendingPathComponent("first")
        try Data("original".utf8).write(to: first)
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let writes = [SelectionWrite(path: first, data: Data("changed".utf8)), SelectionWrite(path: blocked.appendingPathComponent("child"), data: Data("new".utf8))]
        let backup = root.appendingPathComponent("backup")
        XCTAssertThrowsError(try LocaleSelection.apply(writes, backup: backup))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("0.original"), encoding: .utf8), "original")
    }

    func testSystemSelectionRemovesLocaleOverridesButPreservesUnrelatedText() {
        let result = LocaleSelection.systemConfiguration("# keep\nLANG=C\nLC_ALL=C\nLC_TIME=de_AT.UTF-8\nLANGUAGE=de\nOTHER=keep\n", name: "en_GB.UTF-8@custom")
        XCTAssertTrue(result.contains("# keep\n"))
        XCTAssertTrue(result.contains("OTHER=keep\n"))
        XCTAssertTrue(result.contains("LANG=en_GB.UTF-8@custom\n"))
        XCTAssertFalse(result.contains("LC_TIME="))
        XCTAssertFalse(result.contains("LC_ALL="))
        XCTAssertFalse(result.contains("LANGUAGE="))
    }

    func testPreparedPackageReadsRejectSymlinksAndOversizedFiles() throws {
        try Data("abcdef".utf8).write(to: root.appendingPathComponent("real"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("real"))
        XCTAssertThrowsError(try InstallFiles.read(root, "link"))
        XCTAssertThrowsError(try InstallFiles.read(root, "real", limit: 3))
        XCTAssertThrowsError(try InstallFiles.read(root, "../real"))
        let directory = root.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("value".utf8).write(to: directory.appendingPathComponent("value"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: directory)
        XCTAssertThrowsError(try InstallFiles.read(root, "alias/value"))
        XCTAssertEqual(try InstallFiles.read(root, "directory/value"), Data("value".utf8))
    }

    func testUnownedDestinationAndReservedNamesAreProtected() throws {
        let locations = locations()
        let destination = locations.locales.appendingPathComponent("en_GB.UTF-8@foreign")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: destination.appendingPathComponent("keep"))
        XCTAssertThrowsError(try LocaleInstaller.checkDestination(name: destination.lastPathComponent, locations: locations, replacing: true))
        for name in ["C", "POSIX", "../../etc/locale.conf"] {
            try JSONEncoder().encode(InstallManifest(version: 1, name: name)).write(to: root.appendingPathComponent("manifest.json"))
            XCTAssertThrowsError(try LocaleInstaller.manifest(at: root))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("keep").path))
    }

    func testUserInstallSelectReplaceAndShellActivation() throws {
        let (catalog, binary, project) = try native()
        let locations = locations()
        let profile = root.appendingPathComponent("home/.zshrc")
        try FileManager.default.createDirectory(at: profile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# original\nexport EDITOR=vi\n".utf8).write(to: profile)
        let prepared = try PreparedLocaleInstall(project: project, catalog: catalog, worker: binary)
        let result = try LocaleInstaller.install(package: prepared.directory, locations: locations, select: true, replacing: false, worker: binary)
        XCTAssertTrue(result.selected)
        XCTAssertTrue(result.selectionFiles.contains(profile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.destination + "/LC_TIME"))
        let text = try String(contentsOf: profile, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# original\nexport EDITOR=vi\n"))
        XCTAssertEqual(text.components(separatedBy: LocaleSelection.markerStart).count - 1, 1)
        let activation = try XCTUnwrap(result.activationScript)
        let command = ". " + LocaleSelection.quote(activation) + "; printf '%s|%s|%s' \"$LANG\" \"$LOCPATH\" \"${LC_ALL-unset}\""
        let shell = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], environment: ["LC_ALL": "C", "LANGUAGE": "de", "PATH": "/usr/bin:/bin"])
        XCTAssertEqual(shell.status, 0)
        XCTAssertEqual(shell.output, project.name + "|" + locations.locales.path + "|unset")
        XCTAssertThrowsError(try LocaleInstaller.install(package: prepared.directory, locations: locations, select: true, replacing: false, worker: binary))
        var edited = EditorSession(project: project)
        try edited.set(.identification, key: "revision", value: .text("2"))
        let update = try PreparedLocaleInstall(project: edited.project, catalog: catalog, worker: binary)
        let replaced = try LocaleInstaller.install(package: update.directory, locations: locations, select: true, replacing: true, worker: binary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replaced.backupDirectory + "/previous-locale/LC_TIME"))
        XCTAssertEqual(try String(contentsOf: profile, encoding: .utf8), text)
        let installed = try LocaleProject.load(from: URL(fileURLWithPath: replaced.destination).appendingPathComponent("project.json"))
        XCTAssertEqual(try installed.selection(.identification).overrides["revision"], .text("2"))
    }

    func testSystemLayoutAndSelectionUseOnlyAnIsolatedRoot() throws {
        let (catalog, binary, project) = try native()
        let config = root.appendingPathComponent("etc/locale.conf")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("etc/default"), withIntermediateDirectories: true)
        try Data("# original\nLANG=C.UTF-8\nLC_TIME=de_AT.UTF-8\n".utf8).write(to: config)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("etc/default/locale"), withDestinationURL: config)
        let locations = InstallLocations.system(root: root)
        XCTAssertFalse(locations.isRealSystem)
        XCTAssertEqual(locations.systemConfigurations.count, 1)
        let prepared = try PreparedLocaleInstall(project: project, catalog: catalog, worker: binary)
        let result = try LocaleInstaller.install(package: prepared.directory, locations: locations, select: true, replacing: false, worker: binary)
        XCTAssertTrue(result.destination.hasPrefix(root.path + "/"))
        XCTAssertEqual(result.scope, .system)
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).contains("LANG=" + project.name))
        XCTAssertFalse(try String(contentsOf: config, encoding: .utf8).contains("LC_TIME="))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupDirectory + "/selection/0.original"))
        // A verified temporary system layout must not be mistaken for a real system install.
        XCTAssertThrowsError(try LocaleInstaller.verify(name: project.name, root: locations.locales, worker: binary, defaultSearch: true))
    }

    func testFailedSelectionRemovesNewInstallAndRestoresSelectionFiles() throws {
        let (catalog, binary, project) = try native()
        let locations = locations()
        try FileManager.default.createDirectory(at: locations.configuration, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: locations.configuration.appendingPathComponent("environment.d"))
        let prepared = try PreparedLocaleInstall(project: project, catalog: catalog, worker: binary)
        XCTAssertThrowsError(try LocaleInstaller.install(package: prepared.directory, locations: locations, select: true, replacing: false, worker: binary))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.locales.appendingPathComponent(project.name).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.configuration.appendingPathComponent("linux-locale-editor/activate.sh").path))
        XCTAssertEqual(try String(contentsOf: locations.configuration.appendingPathComponent("environment.d"), encoding: .utf8), "not a directory")
    }
}
