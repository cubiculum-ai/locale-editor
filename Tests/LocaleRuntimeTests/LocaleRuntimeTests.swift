import Foundation
import XCTest
import LocaleCore
@testable import LocaleRuntime

final class LocaleRuntimeTests: XCTestCase {
    func testProcessArgumentsAreLiteral() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "$(echo wrong); `false`"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "$(echo wrong); `false`")
    }

    func testWorkerTimeoutIsBounded() throws {
        let start = Date()
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["3"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testGlibcCompositionAndPreview() throws {
        guard LocaleRuntime.supportsGlibc else { throw XCTSkip("Requires Linux/glibc; macOS Foundation is not a locale preview substitute.") }
        let root = URL(fileURLWithPath: "/usr/share/i18n/locales")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("en_GB").path) else { throw XCTSkip("Install the distribution's locale sources.") }
        let catalog = try LocaleCatalog(roots: [root])
        var editor = EditorSession(project: try LocaleProject(name: "en_GB.UTF-8@editor_test", base: "en_GB"))
        try editor.inherit(.numeric, from: "de_AT", catalog: catalog)
        try editor.inherit(.monetary, from: "de_AT", catalog: catalog)
        try editor.inherit(.collate, from: "sv_SE", catalog: catalog)
        try editor.set(.time, key: "d_fmt", value: .text("%Y-%m-%d"))
        let binary: URL
        if let path = ProcessInfo.processInfo.environment["LOCALE_EDITOR_BINARY"] { binary = URL(fileURLWithPath: path) }
        else {
            let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            binary = repo.appendingPathComponent(".build/debug/locale-editor")
        }
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Build locale-editor and set LOCALE_EDITOR_BINARY to its absolute path.") }
        let preview = try LocaleRuntime.preview(editor.project, catalog: catalog, worker: binary, words: ["ä", "z", "a", "å", "ö"])
        XCTAssertEqual(preview.items.first { $0.label == "2026-10-27 Date" }?.value, "2026-10-27")
        XCTAssertEqual(preview.items.first { $0.label == "2000-2-29 Date" }?.value, "2000-02-29")
        XCTAssertEqual(preview.items.first { $0.label == "Number 1234567.89" }?.value, "1.234.567,89")
        XCTAssertTrue(preview.items.first { $0.label == "Currency -1234.5" }?.value.contains("€") == true)
        XCTAssertTrue(preview.items.first { $0.label == "International currency 1234567.89" }?.value.contains("EUR") == true)
        XCTAssertEqual(preview.sortedWords, ["a", "z", "å", "ä", "ö"])
        // Rebuild under the same locale name; fresh workers must see changed formats, not cached data.
        try editor.set(.time, key: "d_fmt", value: .text("%d.%m.%Y"))
        try editor.set(.numeric, key: "decimal_point", value: .text("."))
        try editor.set(.numeric, key: "thousands_sep", value: .text("_"))
        try editor.set(.numeric, key: "grouping", value: .integers([3, 2]))
        try editor.set(.monetary, key: "currency_symbol", value: .text("¤😀"))
        try editor.set(.paper, values: PaperSizes.all.first { $0.id == "fax-safe" }!.overrides)
        try editor.set(.telephone, values: ["tel_int_fmt": .text("+%c(%a)%l"), "int_prefix": .text("43")])
        try editor.set(.address, values: ["postal_fmt": .text("%n%N%s %h%N%z %T%N%c"), "country_isbn": .text("0")])
        try editor.set(.identification, values: ["title": .text("Locale editor example"), "revision": .text("2")])
        try editor.set(.measurement, key: "measurement", value: .integer(2))
        let second = try LocaleRuntime.preview(editor.project, catalog: catalog, worker: binary)
        XCTAssertEqual(second.items.first { $0.label == "2026-10-27 Date" }?.value, "27.10.2026")
        XCTAssertEqual(second.items.first { $0.label == "Number 1234567.89" }?.value, "12_34_567.89")
        XCTAssertTrue(second.items.first { $0.label == "Currency -1234.5" }?.value.contains("¤😀") == true)
        XCTAssertEqual(second.items.first { $0.label == "Paper height (mm)" }?.value, "279")
        XCTAssertEqual(second.items.first { $0.label == "Paper width (mm)" }?.value, "210")
        let phone = try XCTUnwrap(second.items.first { $0.label == "International telephone format" }?.value)
        XCTAssertEqual(try SourceSyntax.unquote(phone, escape: "\\"), "+%c(%a)%l")
        let postal = try XCTUnwrap(second.items.first { $0.label == "Postal address format" }?.value)
        XCTAssertEqual(try SourceSyntax.unquote(postal, escape: "\\"), "%n%N%s %h%N%z %T%N%c")
        let title = try XCTUnwrap(second.items.first { $0.label == "Metadata title" }?.value)
        XCTAssertEqual(try SourceSyntax.unquote(title, escape: "\\"), "Locale editor example")
        XCTAssertEqual(second.items.first { $0.label == "Measurement (1 metric, 2 US)" }?.value, "2")
        let live = try CompiledPreview(project: editor.project, catalog: catalog, worker: binary)
        let samples = try live.formatExamples(["%Y-%m-%d", "%a %d %b %Y %r %Z", "%Y-%m-%d", "", "%A / %B"])
        XCTAssertEqual(samples["%Y-%m-%d"], "2026-10-27")
        XCTAssertEqual(samples[""], "(empty)")
        XCTAssertEqual(samples["%A / %B"], "Tuesday / October")
        XCTAssertTrue(samples["%a %d %b %Y %r %Z"]?.hasPrefix("Tue 27 Oct 2026") == true)
        XCTAssertEqual(samples.count, 4)
        let dateSamples = try live.formatExamples(["%Y-%m-%dT%T%:z", ""], gnuDate: true)
        XCTAssertEqual(dateSamples["%Y-%m-%dT%T%:z"], "2026-10-27T17:04:05+00:00")
        XCTAssertEqual(dateSamples[""], "(empty)")
    }

    func testDistributionSourceCatalog() throws {
        guard LocaleRuntime.supportsGlibc else { throw XCTSkip("Requires a Linux distribution locale source catalog.") }
        let root = URL(fileURLWithPath: "/usr/share/i18n/locales")
        guard FileManager.default.fileExists(atPath: root.path) else { throw XCTSkip("Locale source data is not installed.") }
        let catalog = try LocaleCatalog(roots: [root])
        XCTAssertGreaterThan(catalog.names.count, 100)
        for name in catalog.names {
            XCTAssertNoThrow(try catalog.source(name), "Parse \(name)")
            for category in [LocaleCategory.time, .numeric, .monetary] {
                XCTAssertNoThrow(try catalog.resolve(name, category: category), "Resolve \(name)/\(category.rawValue)")
            }
        }
        let presets = LocalePresetIndex(catalog: catalog)
        XCTAssertGreaterThan(presets.presets(for: .time, field: "d_fmt").count, 10)
        XCTAssertGreaterThan(presets.presets(for: .monetary, field: "currency_symbol").count, 50)
        XCTAssertTrue(presets.diagnostics.isEmpty, presets.diagnostics.joined(separator: "\n"))
    }
}
