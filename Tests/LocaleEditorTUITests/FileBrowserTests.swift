import Foundation
import XCTest
@testable import LocaleEditorTUI

final class FileBrowserTests: XCTestCase {
    func testCompileDestinationAcceptsCurrentOrNewDirectoryButNotFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let browser = try FileBrowser(directory: root)
        XCTAssertEqual(try browser.destination("", mode: .compile).path, root.path)
        XCTAssertEqual(try browser.destination("output", mode: .compile).path, root.appendingPathComponent("output").path)
        try Data().write(to: root.appendingPathComponent("file"))
        XCTAssertThrowsError(try browser.destination("file", mode: .compile))
        XCTAssertThrowsError(try browser.destination("missing/output", mode: .compile))
    }
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("file-browser-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder with spaces"), withIntermediateDirectories: false)
        try Data("{}".utf8).write(to: root.appendingPathComponent("über.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent(".hidden.json"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testDirectoryListingNavigationAndHiddenFiles() throws {
        var browser = try FileBrowser(directory: root)
        XCTAssertEqual(browser.entries.map(\.name), ["..", "folder with spaces", "über.json"])
        try browser.toggleHidden()
        XCTAssertTrue(browser.entries.contains { $0.name == ".hidden.json" })
        try browser.navigate(to: root.appendingPathComponent("folder with spaces"))
        XCTAssertEqual(browser.entries.map(\.name), [".."])
        try browser.navigate(to: browser.entries[0].url)
        XCTAssertEqual(browser.directory.path, root.path)
    }
    func testFailedNavigationPreservesLocationAndListing() throws {
        var browser = try FileBrowser(directory: root)
        let names = browser.entries.map(\.name)
        XCTAssertThrowsError(try browser.navigate(to: root.appendingPathComponent("missing")))
        XCTAssertEqual(browser.directory.path, root.path)
        XCTAssertEqual(browser.entries.map(\.name), names)
    }
    func testDestinationsValidateWithoutCreatingOrWritingFiles() throws {
        let browser = try FileBrowser(directory: root)
        XCTAssertEqual(try browser.destination("über.json", mode: .open).lastPathComponent, "über.json")
        XCTAssertThrowsError(try browser.destination("new.json", mode: .open))
        let new = try browser.destination("new name.json", mode: .save)
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        XCTAssertThrowsError(try browser.destination("missing/new.json", mode: .export))
        XCTAssertThrowsError(try browser.destination("", mode: .save))
        XCTAssertThrowsError(try browser.resolve("bad\0path"))
        XCTAssertEqual(try browser.resolve("folder with spaces/../über.json").path, root.appendingPathComponent("über.json").path)
    }
    func testSymlinkNavigationAndBrokenLinkOverwriteDetection() throws {
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("folder with spaces"))
        let broken = root.appendingPathComponent("broken.json")
        try FileManager.default.createSymbolicLink(at: broken, withDestinationURL: root.appendingPathComponent("missing.json"))
        var browser = try FileBrowser(directory: root)
        XCTAssertTrue(browser.entries.first { $0.name == "link" }?.directory == true)
        try browser.navigate(to: link)
        XCTAssertEqual(browser.directory.path, link.path)
        XCTAssertTrue(FileBrowser.existsIncludingSymlink(broken))
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.path))
        XCTAssertThrowsError(try browser.destination(broken.path, mode: .open))
    }
    func testFileTextBufferEditingDoesNotTreatPathsAsCommands() {
        var text = FileTextBuffer("abc.json")
        text.handle(.home); text.handle(.right); text.handle(.text(" X "))
        XCTAssertEqual(text.text, "a X bc.json")
        text.handle(.clearLine); text.handle(.text("$(test); file.json"))
        XCTAssertEqual(text.text, "$(test); file.json")
        text.handle(.home); _ = text.visible(width: 8); text.click(column: 2)
        XCTAssertEqual(text.cursor, 2)
    }
}
