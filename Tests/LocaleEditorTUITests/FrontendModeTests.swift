import XCTest
@testable import LocaleEditorTUI

final class FrontendModeTests: XCTestCase {
    func testInvocationSelectsFrontendWithoutResolvingAliases() {
        XCTAssertEqual(FrontendMode.preferred(invocation: "/usr/bin/locale-editor", guiAvailable: true), .gui)
        XCTAssertEqual(FrontendMode.preferred(invocation: "locale-edit", guiAvailable: true), .gui)
        XCTAssertEqual(FrontendMode.preferred(invocation: "/usr/bin/locale-editor-tui", guiAvailable: true), .tui)
        XCTAssertEqual(FrontendMode.preferred(invocation: "locale-edit-tui", guiAvailable: true), .tui)
        XCTAssertEqual(FrontendMode.preferred(invocation: "/some-tui/locale-editor", guiAvailable: true), .gui)
        XCTAssertEqual(FrontendMode.preferred(invocation: "locale-editor", guiAvailable: false), .tui)
    }
}
