import Foundation
import XCTest
@testable import LocaleEditorTUI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class SystemInstallTests: XCTestCase {
    func testInteractiveChildRetainsParentProcessGroup() throws {
        let result = try AttachedProcess.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.1"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.processGroup, getpgrp())
    }
}
