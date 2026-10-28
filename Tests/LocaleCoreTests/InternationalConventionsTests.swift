import Foundation
import XCTest
@testable import LocaleCore

final class InternationalConventionsTests: XCTestCase {
    private var catalog: LocaleCatalog {
        get throws {
            try LocaleCatalog(roots: [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Examples/locales")])
        }
    }
    func testInternationalCompositionPreservesLanguageAndIsOneUndoStep() throws {
        for base in ["demo_en", "demo_de"] {
            let catalog = try catalog
            var session = EditorSession(project: try LocaleProject(name: "en_US.UTF-8@international", base: base))
            let before = session.project
            let changes = try InternationalConventions.changes(project: before, catalog: catalog, genericCurrency: true)
            try session.set(changes)
            XCTAssertEqual(try catalog.effectiveValues(.time, project: session.project)["d_fmt"], .text("%Y-%m-%d"))
            XCTAssertEqual(try catalog.effectiveValues(.numeric, project: session.project)["decimal_point"], try catalog.effectiveValues(.numeric, project: before)["decimal_point"])
            XCTAssertEqual(try catalog.effectiveValues(.time, project: session.project)["day"], try catalog.effectiveValues(.time, project: before)["day"])
            XCTAssertEqual(session.project.sections["LC_MESSAGES"], before.sections["LC_MESSAGES"])
            XCTAssertEqual(session.project.sections["LC_ADDRESS"], before.sections["LC_ADDRESS"])
            XCTAssertEqual(try catalog.effectiveValues(.monetary, project: session.project)["int_curr_symbol"], try catalog.effectiveValues(.monetary, project: before)["int_curr_symbol"])
            XCTAssertTrue(try LocaleExporter.render(session.project, catalog: catalog).contains("week 7;19971130;4"))
            session.undo(); XCTAssertEqual(session.project, before)
            session.redo(); XCTAssertEqual(session.project.sections["LC_MONETARY"]?.overrides["currency_symbol"], .text("¤"))
        }
    }
    func testWeekPresetPreservesTheDayListBase() throws {
        for (base, monday) in [(19971130, 2), (19971201, 1)] {
            let values: [String: FieldValue] = ["week": .integers([7, base, 1])]
            let preset = try XCTUnwrap(InternationalConventions.presets(category: .time, field: "first_weekday", values: values).first)
            XCTAssertEqual(preset.value, .integer(monday))
            XCTAssertEqual(preset.related["week"], .integers([7, base, 4]))
        }
        let field = try XCTUnwrap(FieldSchema.field(.time, "week"))
        XCTAssertEqual(try field.parseInput("7;19971130;4"), .integers([7, 19971130, 4]))
        for invalid in ["7;12345678;4", "8;19971130;4", "7;19971130;0", "7;19971130"] { XCTAssertThrowsError(try field.parseInput(invalid)) }
    }
    func testMoneyGroupingMatchesNumbersForBothCurrencyChoices() throws {
        let catalog = try catalog
        for genericCurrency in [false, true] {
            var session = EditorSession(project: try LocaleProject(name: "en_US.UTF-8@money", base: "demo_en"))
            try session.set(.monetary, values: ["currency_symbol": .text("EUR"), "mon_thousands_sep": .text("'"), "mon_grouping": .integers([3, 2]), "mon_decimal_point": .text(","), "frac_digits": .integer(3)])
            let before = session.project
            let changes = try InternationalConventions.changes(project: before, catalog: catalog, genericCurrency: genericCurrency)
            try session.set(changes)
            let numbers = try catalog.effectiveValues(.numeric, project: session.project)
            let money = try catalog.effectiveValues(.monetary, project: session.project)
            XCTAssertEqual(money["mon_thousands_sep"], numbers["thousands_sep"])
            XCTAssertEqual(money["mon_grouping"], numbers["grouping"])
            XCTAssertEqual(money["mon_thousands_sep"], .text("\u{202F}"))
            XCTAssertEqual(money["mon_grouping"], .integers([3, 3]))
            XCTAssertEqual(money["currency_symbol"], .text(genericCurrency ? "¤" : "EUR"))
            XCTAssertEqual(money["mon_decimal_point"], .text(","))
            XCTAssertEqual(money["frac_digits"], .integer(3))
            let source = try LocaleExporter.render(session.project, catalog: catalog)
            XCTAssertTrue(source.contains("mon_thousands_sep \"<U202F>\""))
            XCTAssertTrue(source.contains("mon_grouping 3;3"))
            session.undo(); XCTAssertEqual(session.project, before)
            session.redo(); XCTAssertEqual(try catalog.effectiveValues(.monetary, project: session.project)["mon_thousands_sep"], .text("\u{202F}"))
        }
    }
    func testNamesAndResponsesExportAndRoundTrip() throws {
        var session = EditorSession(project: try LocaleProject(name: "de_DE.UTF-8@names", base: "demo_de"))
        try session.set(.name, values: ["name_fmt": .text("%f, %g%t%m"), "name_gen": .text("Dr.")])
        try session.set(.messages, values: ["yesstr": .text("ja"), "nostr": .text("nein"), "yesexpr": .text("^([jJ]a|[yY]es)$"), "noexpr": .text("^([nN]ein|[nN]o)$")])
        let text = try LocaleExporter.render(session.project, catalog: catalog)
        let source = try LocaleSource.parse(text, name: "names")
        XCTAssertEqual(source.sections[.name]?.entry("name_fmt")?.value, "\"%f, %g%t%m\"")
        let data = try JSONEncoder().encode(session.project)
        XCTAssertEqual(try JSONDecoder().decode(LocaleProject.self, from: data), session.project)
        XCTAssertEqual(PersonalNames.sample("name_fmt", values: try catalog.effectiveValues(.name, project: session.project)), "Example, Alex Robin")
    }
    func testConditionalNameSpacingAndUnknownDescriptors() {
        XCTAssertEqual(PersonalNames.render("%d%t%g%t%m%t%f %% %Q", fields: ["d": "", "g": "Alex", "m": "", "f": "Example"]), "Alex Example % %Q")
        XCTAssertEqual(PersonalNames.sample("name_mr", values: ["name_fmt": .text("%d%t%g%t%f"), "name_mr": .text("Herr")]), "Herr Alex Example")
    }
    func testPresetProvenanceAndOptionalCurrency() throws {
        XCTAssertEqual(InternationalConventions.presets(category: .time, field: "d_fmt", values: [:]).first?.value, .text("%Y-%m-%d"))
        XCTAssertEqual(InternationalConventions.presets(category: .telephone, field: "tel_int_fmt", values: [:]).first?.value, .text("+%c%a%l"))
        XCTAssertEqual(InternationalConventions.presets(category: .monetary, field: "currency_symbol", values: [:]).first?.value, .text("¤"))
        XCTAssertFalse(InternationalConventions.presets(category: .name, field: "name_fmt", values: [:]).contains { $0.label.contains("International standard") })
        let project = try LocaleProject(name: "en_US.UTF-8@test", base: "demo_en")
        XCTAssertNil(try InternationalConventions.changes(project: project, catalog: catalog, genericCurrency: false)[.monetary]?["currency_symbol"])
        XCTAssertEqual(PaperSizes.all.first?.id, "a4")
        let firstLocal = PaperSizes.all.firstIndex { !$0.isInternationalStandard }!
        XCTAssertTrue(PaperSizes.all[..<firstLocal].allSatisfy(\.isInternationalStandard))
        XCTAssertTrue(PaperSizes.all[firstLocal...].allSatisfy { !$0.isInternationalStandard })
    }
}
