import Foundation
import XCTest
import LocaleCore
@testable import LocaleRuntime

final class InternationalRuntimeTests: XCTestCase {
    private func fixtures() throws -> (LocaleCatalog, URL) {
        guard LocaleRuntime.supportsGlibc else { throw XCTSkip("Requires native glibc.") }
        let catalog = try LocaleCatalog(roots: [URL(fileURLWithPath: "/usr/share/i18n/locales")])
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = ProcessInfo.processInfo.environment["LOCALE_EDITOR_BINARY"].map { URL(fileURLWithPath: $0) } ?? repo.appendingPathComponent(".build/debug/locale-editor")
        return (catalog, binary)
    }
    func testEnglishAndGermanInternationalLocalesCompileAndPreserveLanguage() throws {
        let (catalog, binary) = try fixtures()
        for base in ["en_US", "de_DE"] {
            var editor = EditorSession(project: try LocaleProject(name: base + ".UTF-8@international_test", base: base))
            try editor.set(InternationalConventions.changes(project: editor.project, catalog: catalog, genericCurrency: true))
            try editor.set(.name, values: ["name_fmt": .text("%f, %g%t%m"), "name_gen": .text("Dr.")])
            try editor.set(.messages, values: ["yesexpr": .text("^([yY]es|[jJ]a)$"), "noexpr": .text("^([nN]o|[nN]ein)$")])
            let live = try CompiledPreview(project: editor.project, catalog: catalog, worker: binary)
            let report = try live.report(words: [])
            func value(_ label: String) -> String? { report.items.first { $0.label == label }?.value }
            XCTAssertEqual(value("2026-10-27 Date"), "2026-10-27")
            XCTAssertEqual(value("2026-10-27 Time"), "17:04:05")
            XCTAssertEqual(value("Paper width (mm)"), "210")
            XCTAssertEqual(value("Paper height (mm)"), "297")
            XCTAssertEqual(value("First weekday (offset from week base)"), "2")
            XCTAssertEqual(value("Minimum days in week 1"), "4")
            XCTAssertEqual(value("Measurement (1 metric, 2 US)"), "1")
            XCTAssertTrue(value("Currency 1234567.89")?.contains("¤") == true)
            let amount = base == "de_DE" ? "1\u{202F}234\u{202F}567,89" : "1\u{202F}234\u{202F}567.89"
            XCTAssertEqual(value("Number 1234567.89"), amount)
            XCTAssertTrue(value("Currency 1234567.89")?.contains(amount) == true)
            XCTAssertTrue(value("International currency 1234567.89")?.contains(amount) == true)
            let formats = try live.formatExamples(["%A / %B", "%G-W%V-%u"])
            XCTAssertEqual(formats["%A / %B"], base == "de_DE" ? "Dienstag / Oktober" : "Tuesday / October")
            XCTAssertEqual(formats["%G-W%V-%u"], "2026-W44-2")
            let behaviors = try live.behaviorExamples(BehaviorRequest(patterns: ["^([yY]es|[jJ]a)$", "[", "^$"], responses: ["yes", "ja", "yesterday", "no", ""], characters: "äöü Iıİi"))
            XCTAssertEqual(behaviors.matchedResponses(for: "^([yY]es|[jJ]a)$"), ["yes", "ja"])
            XCTAssertEqual(behaviors.matchedResponses(for: "^$"), [""])
            XCTAssertNotNil(behaviors.error(for: "["))
            let composed = "é", decomposed = "e\u{0301}"
            let exact = try live.behaviorExamples(BehaviorRequest(patterns: ["^" + composed + "$", "^" + decomposed + "$"], responses: [composed, decomposed]))
            XCTAssertEqual(exact.matchedResponses(for: "^" + composed + "$").map { SourceSyntax.quote($0) }, [SourceSyntax.quote(composed)])
            XCTAssertEqual(exact.matchedResponses(for: "^" + decomposed + "$").map { SourceSyntax.quote($0) }, [SourceSyntax.quote(decomposed)])
            XCTAssertTrue(behaviors.uppercase.hasPrefix("ÄÖÜ"))
            XCTAssertTrue(behaviors.characters.first?.value.contains("letter") == true)
            XCTAssertTrue(behaviors.transliteration.hasPrefix(base == "de_DE" ? "aeoeue" : "aou"))
        }
    }
    func testMoneyGroupingWithCurrencyRetained() throws {
        let (catalog, binary) = try fixtures()
        for base in ["en_US", "de_DE"] {
            var editor = EditorSession(project: try LocaleProject(name: base + ".UTF-8@money_test", base: base))
            try editor.set(.monetary, values: ["mon_thousands_sep": .text("'"), "mon_grouping": .integers([3, 2])])
            try editor.set(InternationalConventions.changes(project: editor.project, catalog: catalog, genericCurrency: false))
            let live = try CompiledPreview(project: editor.project, catalog: catalog, worker: binary)
            let report = try live.report(words: [])
            func value(_ label: String) throws -> String { try XCTUnwrap(report.items.first { $0.label == label }?.value) }
            let amount = base == "de_DE" ? "1\u{202F}234\u{202F}567,89" : "1\u{202F}234\u{202F}567.89"
            XCTAssertTrue(try value("Currency 1234567.89").contains(amount))
            XCTAssertTrue(try value("Currency 1234567.89").contains(base == "de_DE" ? "€" : "$"))
            XCTAssertTrue(try value("International currency 1234567.89").contains(amount))
            XCTAssertTrue(try value("International currency 1234567.89").contains(base == "de_DE" ? "EUR" : "USD"))
            XCTAssertTrue(try value("Currency -1234.5").contains(base == "de_DE" ? "1\u{202F}234,50" : "1\u{202F}234.50"))
        }
    }
    func testInternationalCharacterAndSortingProfilesCompile() throws {
        let (catalog, binary) = try fixtures()
        XCTAssertEqual(SectionProfiles.choices(.ctype, catalog: catalog).first?.source, "i18n")
        XCTAssertEqual(SectionProfiles.choices(.collate, catalog: catalog).first?.source, "iso14651_t1")
        for profile in ["i18n", "i18n_ctype", "tr_TR"] {
            var editor = EditorSession(project: try LocaleProject(name: "en_US.UTF-8@profile_test", base: "en_US"))
            try editor.inherit(.ctype, from: profile, catalog: catalog)
            try editor.inherit(.collate, from: "iso14651_t1", catalog: catalog)
            let live = try CompiledPreview(project: editor.project, catalog: catalog, worker: binary)
            let behavior = try live.behaviorExamples(BehaviorRequest(characters: "iI ä0!"))
            XCTAssertTrue(behavior.uppercase.hasPrefix(profile == "tr_TR" ? "İI" : "II"))
            XCTAssertTrue(behavior.lowercase.hasPrefix(profile == "tr_TR" ? "iı" : "ii"))
            XCTAssertEqual(try live.report(words: ["z", "a"]).sortedWords, ["a", "z"])
        }
    }
}
