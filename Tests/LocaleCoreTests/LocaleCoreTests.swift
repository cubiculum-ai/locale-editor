import Foundation
import XCTest
@testable import LocaleCore

final class LocaleCoreTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("locale-core-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    private func write(_ name: String, _ source: String) throws {
        try source.write(to: temporary.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private var examples: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Examples/locales")
    }
    private func demoCatalog() throws -> LocaleCatalog { try LocaleCatalog(roots: [temporary, examples]) }

    func testRoundTripUnicodeAndReservedCharacters() throws {
        let value = "März / \\ \" <U0041> ; % 日本語 😀"
        XCTAssertEqual(try SourceSyntax.unquote(SourceSyntax.quote(value), escape: "/"), value)
        XCTAssertEqual(SourceSyntax.quote("😀"), "\"<U0001F600>\"")
    }

    func testContinuationAndCommentsRespectQuotes() throws {
        let source = try LocaleSource.parse("""
        escape_char   /
        comment_char    %
        LC_TIME
        d_fmt "%Y//%m//%d" % comment
        am_pm "A;M";/
        "P%M"
        END LC_TIME
        """, name: "fixture")
        let section = try XCTUnwrap(source.sections[.time])
        XCTAssertEqual(try SourceSyntax.unquote(section.entry("d_fmt")!.value, escape: "/"), "%Y/%m/%d")
        let parts = try SourceSyntax.splitValues(section.entry("am_pm")!.value, escape: "/")
        XCTAssertEqual(try parts.map { try SourceSyntax.unquote($0, escape: "/") }, ["A;M", "P%M"])
    }

    func testMalformedSourcesFailWithContext() {
        for text in ["LC_TIME\nEND LC_NUMERIC", "LC_TIME\nd_fmt \"%Y\"", "LC_TIME\nLC_NUMERIC\nEND LC_NUMERIC"] {
            XCTAssertThrowsError(try LocaleSource.parse(text, name: "broken"))
        }
    }

    func testRecursiveInheritanceAndUnknownFieldPreservation() throws {
        try write("child", "LC_TIME\ncopy \"middle\"\nEND LC_TIME\n")
        try write("middle", "LC_TIME\ncopy \"parent\"\nEND LC_TIME\n")
        try write("parent", "LC_TIME\nd_fmt \"%d/%m/%Y\"\nfuture_field \"keep/me\"\nEND LC_TIME\n")
        let catalog = try demoCatalog()
        var project = try LocaleProject(name: "en_GB.UTF-8@mine", base: "demo_en")
        project.sections[LocaleCategory.time.rawValue] = CategorySelection(source: "child", overrides: ["d_fmt": .text("%Y-%m-%d")])
        let result = try LocaleExporter.render(project, catalog: catalog)
        XCTAssertTrue(result.contains("d_fmt \"%Y-%m-%d\""))
        XCTAssertTrue(result.contains("future_field \"keep//me\""))
        XCTAssertFalse(result.contains("copy \"child\""))
        XCTAssertTrue(result.contains("LC_COLLATE\ncopy \"demo_en\"\nEND LC_COLLATE"))
        XCTAssertEqual(try catalog.resolve("child", category: .time).origin, "parent")
    }

    func testCycleAndMissingParentFailWithoutHanging() throws {
        try write("a", "LC_TIME\ncopy \"b\"\nEND LC_TIME\n")
        try write("b", "LC_TIME\ncopy \"a\"\nEND LC_TIME\n")
        let catalog = try demoCatalog()
        XCTAssertThrowsError(try catalog.resolve("a", category: .time)) { XCTAssertTrue($0.localizedDescription.contains("cycle")) }
        XCTAssertThrowsError(try catalog.resolve("missing", category: .time))
    }

    func testIllegalCopyWithOverridesIsRejected() throws {
        try write("bad", "LC_TIME\ncopy \"demo_en\"\nd_fmt \"%Y\"\nEND LC_TIME\n")
        XCTAssertThrowsError(try demoCatalog().resolve("bad", category: .time))
    }

    func testWholeCategoryInheritanceAndEditableMaterialization() throws {
        let catalog = try demoCatalog()
        var editor = EditorSession(project: try LocaleProject(name: "en_GB.UTF-8@personal", base: "demo_en"))
        try editor.inherit(.numeric, from: "demo_de", catalog: catalog)
        var output = try LocaleExporter.render(editor.project, catalog: catalog)
        XCTAssertTrue(output.contains("LC_NUMERIC\ncopy \"demo_de\"\nEND LC_NUMERIC"))
        try editor.set(.numeric, key: "thousands_sep", value: .text("’"))
        output = try LocaleExporter.render(editor.project, catalog: catalog)
        XCTAssertTrue(output.contains("decimal_point \",\""))
        XCTAssertTrue(output.contains("thousands_sep \"<U2019>\""))
        XCTAssertTrue(output.contains("grouping 3;3"))
    }

    func testParentChangeRetainsOverridesResetFollowsNewParentAndUndoRedo() throws {
        let catalog = try demoCatalog()
        var editor = EditorSession(project: try LocaleProject(name: "en_GB.UTF-8@test", base: "demo_en"))
        try editor.set(.numeric, key: "decimal_point", value: .text("·"))
        try editor.inherit(.numeric, from: "demo_de", catalog: catalog)
        XCTAssertEqual(try editor.project.selection(.numeric).overrides["decimal_point"], .text("·"))
        try editor.reset(.numeric, key: "decimal_point")
        XCTAssertNil(try editor.project.selection(.numeric).overrides["decimal_point"])
        let field = try XCTUnwrap(FieldSchema.field(.numeric, "decimal_point"))
        XCTAssertEqual(try catalog.inheritedValue(field, category: .numeric, project: editor.project), .text(","))
        editor.undo()
        XCTAssertEqual(try editor.project.selection(.numeric).overrides["decimal_point"], .text("·"))
        editor.redo()
        XCTAssertNil(try editor.project.selection(.numeric).overrides["decimal_point"])
    }

    func testValidationIsTransactionalAndBlocksSourceInjection() throws {
        var editor = EditorSession(project: try LocaleProject(name: "test.UTF-8", base: "demo_en"))
        let before = editor.project
        XCTAssertThrowsError(try editor.set(.numeric, key: "decimal_point", value: .text(".\nEND LC_NUMERIC")))
        XCTAssertEqual(editor.project, before)
        XCTAssertFalse(editor.canUndo)
        XCTAssertThrowsError(try editor.set(.time, key: "first_weekday", value: .integer(8)))
        XCTAssertThrowsError(try editor.set(.ctype, key: "made_up", value: .text("x")))
        XCTAssertThrowsError(try editor.rename("../../etc/locale"))
        XCTAssertThrowsError(try editor.set(.numeric, key: "decimal_point", value: .text("..")))
    }

    func testFieldParsingAndConstraints() throws {
        let grouping = try XCTUnwrap(FieldSchema.field(.numeric, "grouping"))
        XCTAssertEqual(try grouping.parseInput("3;2"), .integers([3, 2]))
        XCTAssertEqual(try grouping.parseInput("3;2;"), .integers([3, 2]))
        XCTAssertEqual(try grouping.parseInput("-1"), .integers([-1]))
        XCTAssertEqual(try grouping.parseInput("0;0"), .integers([0, 0]))
        XCTAssertEqual(try grouping.parseInput("3;0"), .integers([3, 0]))
        XCTAssertEqual(try grouping.parseInput("126"), .integers([126]))
        XCTAssertThrowsError(try grouping.parseInput("127"))
        XCTAssertThrowsError(try grouping.parseInput("3;-1;2"))
        let days = try XCTUnwrap(FieldSchema.field(.time, "day"))
        XCTAssertThrowsError(try days.parseInput("Sunday | Monday"))
        let format = try XCTUnwrap(FieldSchema.field(.time, "d_fmt"))
        XCTAssertEqual(try format.parseInput("%Q"), .text("%Q")) // libc preserves unknown conversions literally
        XCTAssertThrowsError(try format.parseInput("%"))
        XCTAssertEqual(try format.parseInput("%Y-%m-%d"), .text("%Y-%m-%d"))
        XCTAssertEqual(try format.parseInput("%l:%M:%S %P %Z"), .text("%l:%M:%S %P %Z"))
        XCTAssertEqual(try format.parseInput("%Y-%m-%dT%T%:z"), .text("%Y-%m-%dT%T%:z"))
    }

    func testDirectAndIndirectRecursiveDateFormatsAreRejected() throws {
        let catalog = try demoCatalog()
        var project = try LocaleProject(name: "test.UTF-8", base: "demo_en")
        project.sections[LocaleCategory.time.rawValue]?.overrides["d_fmt"] = .text("%x")
        XCTAssertThrowsError(try LocaleExporter.render(project, catalog: catalog))
        project.sections[LocaleCategory.time.rawValue]?.overrides = ["d_fmt": .text("%X"), "t_fmt": .text("%x")]
        XCTAssertThrowsError(try LocaleExporter.render(project, catalog: catalog))
    }

    func testSaveReloadAndDirtyTracking() throws {
        let catalog = try demoCatalog()
        var editor = EditorSession(project: try LocaleProject(name: "test.UTF-8", base: "demo_en"))
        try editor.set(.time, key: "d_fmt", value: .text("%Y-%m-%d"))
        XCTAssertTrue(editor.isDirty)
        let file = temporary.appendingPathComponent("project.json")
        try editor.save(to: file, catalog: catalog)
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(try LocaleProject.load(from: file), editor.project)
        try editor.set(.paper, key: "height", value: .integer(300))
        editor.undo()
        XCTAssertFalse(editor.isDirty)
    }

    func testSourceChangeDetectionIncludesParentDependencies() throws {
        let original = try String(contentsOf: examples.appendingPathComponent("demo_en"), encoding: .utf8)
        try write("demo_en", original)
        let catalog = try demoCatalog()
        var project = try LocaleProject(name: "test.UTF-8", base: "demo_de")
        project.sourceFingerprints = try catalog.fingerprints(for: project)
        XCTAssertTrue(try catalog.changedSources(for: project).isEmpty)
        try write("demo_en", original + "\n% Upstream update\n")
        XCTAssertEqual(try catalog.changedSources(for: project), ["demo_en"])
    }

    func testUnknownProjectVersionsAndFieldsFailRatherThanDroppingData() throws {
        var project = try LocaleProject(name: "test.UTF-8", base: "demo_en")
        project.version = 2
        XCTAssertThrowsError(try project.validate())
        project.version = 1
        project.sections["LC_FUTURE"] = CategorySelection(source: "demo_en")
        XCTAssertThrowsError(try project.validate())
    }

    func testPresetsResolveInheritanceAndDeduplicateDecodedDefinitions() throws {
        try write("same", "LC_TIME\nd_fmt \"<U0025>Y-<U0025>m-<U0025>d\"\nEND LC_TIME\n")
        try write("direct", "LC_TIME\nd_fmt \"%Y-%m-%d\"\nEND LC_TIME\n")
        try write("alias", "LC_TIME\ncopy \"direct\"\nEND LC_TIME\n")
        let index = LocalePresetIndex(catalog: try demoCatalog())
        let matches = index.presets(for: .time, field: "d_fmt").filter { $0.value == .text("%Y-%m-%d") }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.sources, ["alias", "direct", "same"])
        XCTAssertEqual(index.presets(for: .numeric, field: "decimal_point").count, 2)
    }

    func testContinuedQuotedFormatsKeepPercentCodes() throws {
        let source = try LocaleSource.parse("""
        comment_char %
        escape_char /
        LC_TIME
        d_fmt "སྤྱི་ལོ%y/
        ཟླ%mཚེས%d"
        END LC_TIME
        """, name: "continued")
        let entry = try XCTUnwrap(source.sections[.time]?.entry("d_fmt"))
        XCTAssertEqual(try SourceSyntax.unquote(entry.value, escape: "/"), "སྤྱི་ལོ%yཟླ%mཚེས%d")
    }

    func testContinuationAfterInlineCommentsKeepsListEntries() throws {
        let source = try LocaleSource.parse("""
        escape_char /
        comment_char %
        LC_TIME
        am_pm /
        "AM"; % morning /
        "PM" % afternoon
        END LC_TIME
        """, name: "comments")
        let entry = try XCTUnwrap(source.sections[.time]?.entry("am_pm"))
        let field = try XCTUnwrap(FieldSchema.field(.time, "am_pm"))
        XCTAssertEqual(try field.decodeSource(entry.value, escape: "/"), .strings(["AM", "PM"]))
    }

    func testCurrencyCatalogIncludesUnicodeSymbolsOutsideCurrencyBlock() throws {
        let symbols = CurrencySymbols.all
        XCTAssertEqual(symbols.count, 67)
        XCTAssertEqual(Set(symbols.map(\.scalar)).count, symbols.count)
        for scalar: UInt32 in [0x24, 0x20AC, 0x20B9, 0x20BF, 0x0E3F, 0x11FDD, 0x1ECB0] {
            XCTAssertTrue(symbols.contains { $0.scalar == scalar })
        }
        XCTAssertTrue(symbols.allSatisfy { !$0.name.isEmpty && UnicodeScalar($0.scalar) != nil })
    }

    func testCurrencyDirectionalMarksArePreservedAndControlsRejected() throws {
        let field = try XCTUnwrap(FieldSchema.field(.monetary, "currency_symbol"))
        let symbol = "د.إ.\u{200F}"
        XCTAssertEqual(try field.parseInput(symbol), .text(symbol))
        XCTAssertThrowsError(try field.parseInput("USD\n"))
        XCTAssertEqual(try SourceSyntax.unquote(FieldValue.text(symbol).source, escape: "/"), symbol)
    }

    func testCandidateExamplesUseGroupingAndCurrencyPlacement() throws {
        let catalog = try demoCatalog(), project = try LocaleProject(name: "test.UTF-8", base: "demo_de")
        var values = try catalog.effectiveValues(.numeric, project: project)
        values["grouping"] = .integers([3, 2]); values["thousands_sep"] = .text("_")
        XCTAssertEqual(FieldExamples.number(values: values), "12_34_567,89")
        values["grouping"] = .integers([0, 0])
        XCTAssertEqual(FieldExamples.number(values: values), "1234567,89")
        values["grouping"] = .integers([3, 0])
        XCTAssertEqual(FieldExamples.number(values: values), "1234_567,89")
        values["grouping"] = .integers([3])
        XCTAssertEqual(FieldExamples.number(values: values), "1_234_567,89")
        var money = try catalog.effectiveValues(.monetary, project: project)
        money["currency_symbol"] = .text("₿")
        XCTAssertEqual(FieldExamples.money(values: money), "1.234.567,89 ₿")
        XCTAssertEqual(FieldExamples.money(values: money, negative: true), "-1.234.567,89 ₿")
        let international = try XCTUnwrap(FieldSchema.field(.monetary, "int_curr_symbol"))
        XCTAssertEqual(FieldExamples.example(international, category: .monetary, values: money), "1.234.567,89 EUR")
        var dates = try catalog.effectiveValues(.time, project: project)
        dates.removeValue(forKey: "first_workday")
        XCTAssertEqual(FieldExamples.example(FieldSchema.field(.time, "first_workday")!, category: .time, values: dates), "Montag")
    }

    func testNamedPaperSizeChangesAndResetsBothDimensionsAtomically() throws {
        let initial = try LocaleProject(name: "en_GB.UTF-8@paper", base: "demo_en")
        var session = EditorSession(project: initial)
        let fax = try XCTUnwrap(PaperSizes.all.first { $0.id == "fax-safe" })
        XCTAssertEqual(fax.width, 210)
        XCTAssertLessThanOrEqual(Double(fax.height), 279.4)
        try session.set(.paper, values: fax.overrides)
        XCTAssertEqual(try session.project.selection(.paper).overrides, ["width": .integer(210), "height": .integer(279)])
        session.undo()
        XCTAssertEqual(session.project, initial)
        session.redo()
        let before = session.project
        XCTAssertThrowsError(try session.set(.paper, values: ["width": .integer(200), "height": .integer(0)]))
        XCTAssertEqual(session.project, before)
        try session.reset(.paper, keys: ["width", "height"])
        XCTAssertTrue(try session.project.selection(.paper).overrides.isEmpty)
    }

    func testNamedPaperAndTelephoneExportOnlyRealLocaleFields() throws {
        let catalog = try demoCatalog()
        var session = EditorSession(project: try LocaleProject(name: "en_GB.UTF-8@formats", base: "demo_en"))
        try session.set(.paper, values: PaperSizes.all.first { $0.id == "fax-safe" }!.overrides)
        try session.set(.telephone, key: "tel_int_fmt", value: .text("+%c(%a)%l"))
        let output = try LocaleExporter.render(session.project, catalog: catalog)
        XCTAssertTrue(output.contains("height 279"))
        XCTAssertTrue(output.contains("width 210"))
        XCTAssertTrue(output.contains("tel_int_fmt \"+%c(%a)%l\""))
        XCTAssertFalse(output.contains("paper_size"))
        XCTAssertEqual(PaperSizes.name(values: ["width": .integer(210), "height": .integer(297)]), "A4")
        XCTAssertEqual(PaperSizes.name(values: ["width": .integer(297), "height": .integer(210)]), "A4 (landscape)")
        XCTAssertEqual(PaperSizes.name(values: ["width": .integer(210), "height": .integer(279)]), "Fax-safe")
    }

    func testTelephoneExamplesPreserveRequestedPunctuationAndConditionalSpacing() {
        XCTAssertEqual(TelephoneFormats.render("+%c(%a)%l"), "+43(1)5550123")
        XCTAssertEqual(TelephoneFormats.render("+%c%a%l"), "+4315550123")
        XCTAssertEqual(TelephoneFormats.render("%e%t%l"), "5550123")
        XCTAssertEqual(TelephoneFormats.render("%e%t%l", extensionNumber: "99"), "99 5550123")
        XCTAssertEqual(TelephoneFormats.sample("tel_int_fmt", values: ["int_prefix": .text("1"), "tel_int_fmt": .text("+%c(%a)%l")]), "+1(202)5550123")
    }

    func testPostalFormattingHandlesConditionalLinesSpacesAndRomanizedFields() {
        let sample = PostalAddressSample(fields: ["n": "Alex Example", "a": "", "s": "通り", "h": "12", "z": "12345", "T": "Sample City"], romanized: ["s": "Street"])
        XCTAssertEqual(PostalAddresses.render("%n%N%a%N%h %Rs%N%z%t%T", sample: sample), "Alex Example\n12 Street\n12345 Sample City")
        XCTAssertEqual(PostalAddresses.render("%a%t%n", sample: sample), "Alex Example")
        XCTAssertEqual(PostalAddresses.render("%% %s", sample: sample), "% 通り")
    }

    func testPostalPresetsAndMetadataSurviveExportAndProjectReload() throws {
        let catalog = try demoCatalog()
        var session = EditorSession(project: try LocaleProject(name: "en_GB.UTF-8@postal", base: "demo_en"))
        try session.set(.address, key: "postal_fmt", value: .text("%n%N%s %h%N%z %T%N%c"))
        try session.set(.identification, values: ["title": .text("My locale — test"), "revision": .text("2"), "contact": .text("Example Maintainer")])
        let source = try LocaleExporter.render(session.project, catalog: catalog)
        XCTAssertTrue(source.contains("postal_fmt \"%n%N%s %h%N%z %T%N%c\""))
        XCTAssertTrue(source.contains("category \"i18n:2012\";LC_TIME"))
        XCTAssertTrue(source.contains("revision \"2\""))
        let path = temporary.appendingPathComponent("postal.json")
        try session.save(to: path, catalog: catalog)
        XCTAssertEqual(try LocaleProject.load(from: path), session.project)
        let index = LocalePresetIndex(catalog: catalog)
        XCTAssertFalse(index.presets(for: .address, field: "postal_fmt").isEmpty)
        XCTAssertFalse(index.presets(for: .identification, field: "title").isEmpty)
        let isbn = try XCTUnwrap(FieldSchema.field(.address, "country_isbn"))
        XCTAssertEqual(try isbn.decodeSource("99928", escape: "/"), .text("99928"))
        XCTAssertEqual(try isbn.decodeSource("\"99928\"", escape: "/"), .text("99928"))
    }
}
