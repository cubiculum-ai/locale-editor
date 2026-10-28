import Foundation
import XCTest
@testable import LocaleRuntime

final class AdministratorInstallTests: XCTestCase {
    func testPolkitUsesExplicitHelperArgumentsAndNoGraphicalRootSession() {
        let package = URL(fileURLWithPath: "/tmp/a package; literal")
        let worker = URL(fileURLWithPath: "/usr/bin/locale-editor")
        XCTAssertEqual(AdministratorInstall.arguments(package: package, select: true, replacing: true, worker: worker, graphical: true),
                       ["--disable-internal-agent", "/usr/bin/locale-editor", "--install-system", "/tmp/a package; literal", "--select", "--replace"])
        XCTAssertEqual(AdministratorInstall.arguments(package: package, select: false, replacing: false, worker: worker, graphical: false),
                       ["/usr/bin/locale-editor", "--install-system", "/tmp/a package; literal"])
    }
    func testCancellationIsNotSuccessAndDenialReportsFailure() throws {
        XCTAssertNil(try AdministratorInstall.decode(status: 126, output: "cancelled"))
        XCTAssertThrowsError(try AdministratorInstall.decode(status: 127, output: "Not authorized"))
        XCTAssertThrowsError(try AdministratorInstall.decode(status: 0, output: "not a receipt"))
        let output = #"{"name":"en_US.UTF-8@test","scope":"system","destination":"/usr/lib/locale/en_US.UTF-8@test","selected":false,"selectionFiles":[],"backupDirectory":"/var/lib/linux-locale-editor/backups/test"}"#
        let result = try XCTUnwrap(AdministratorInstall.decode(status: 0, output: output))
        XCTAssertEqual(result.name, "en_US.UTF-8@test")
        XCTAssertFalse(result.selected)
    }
}
