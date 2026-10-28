import Foundation
import Dispatch
import XCTest
@testable import LocaleRuntime

private final class WorkerFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
}

final class ProcessRunnerTests: XCTestCase {
    func testFastWorkersAreReapedWithoutAUIRunLoop() throws {
        for _ in 0..<100 {
            let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeout: 2)
            XCTAssertEqual(result.status, 0)
        }
    }
    func testConcurrentWorkersKeepTheirOutputSeparate() {
        let failures = WorkerFailures()
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            do {
                let text = "worker-\(index)-ä-😀"
                let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", text], timeout: 5)
                if result.status != 0 || result.output != text { failures.add("Worker \(index): \(result.output)") }
            } catch { failures.add(error.localizedDescription) }
        }
        XCTAssertEqual(failures.all(), [])
    }
    func testExitStatusAndMergedDiagnostics() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf out; sleep 0.03; printf err >&2; exit 7"], timeout: 2)
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output, "outerr")
    }
    func testLinuxEnvironmentAndArgumentValidation() throws {
        #if os(Linux)
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/env"), arguments: [], environment: ["ONLY": "literal $(false) ä"])
        XCTAssertEqual(result.output, "ONLY=literal $(false) ä\n")
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: ["a\0b"]))
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [], environment: ["BAD=KEY": "value"]))
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/nonexistent/locale-editor-test-command"), arguments: []))
        #endif
    }
    func testTimeoutStopsTheWorkersSubprocessGroup() throws {
        #if os(Linux)
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("locale-timeout-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 1; printf alive > \"$1\"", "sh", marker.path], timeout: 0.05))
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        #endif
    }
}
