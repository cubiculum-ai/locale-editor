import Foundation
import Dispatch
import LocaleCore
import CLocaleBridge
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct ProcessResult {
    public let status: Int32
    public let output: String
}

public enum ProcessRunner {
    /// Argument arrays and file-backed output avoid shell interpretation and pipe deadlocks.
    /// Linux children are reaped directly: Foundation's Process.waitUntilExit has stalled
    /// with an already-exited worker on arm64. No UI run loop is required for these workers.
    public static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval = 20) throws -> ProcessResult {
        guard timeout.isFinite, timeout >= 0, timeout <= 86400 else { throw LocaleEditorError("Invalid process time limit.") }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("locale-editor-process-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw LocaleEditorError("Cannot create temporary process output file.")
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let status: Int32
        #if os(Linux)
        let strings = [executable.path] + arguments
        let variables = environment ?? ProcessInfo.processInfo.environment
        guard strings.allSatisfy({ !$0.utf8.contains(0) }), variables.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.utf8.contains(0) && !$0.value.utf8.contains(0) }) else {
            throw LocaleEditorError("Process arguments and environment must not contain NUL or invalid variable names.")
        }
        var argv = strings.map { strdup($0) } + [nil]
        var envp = variables.keys.sorted().map { strdup($0 + "=" + variables[$0]!) } + [nil]
        defer { for value in argv { free(value) }; for value in envp { free(value) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else { throw LocaleEditorError("Cannot allocate process arguments.") }
        var spawnError: Int32 = 0
        let pid = argv.withUnsafeMutableBufferPointer { args in
            envp.withUnsafeMutableBufferPointer { env in
                le_spawn_capture(executable.path, args.baseAddress, env.baseAddress, output.fileDescriptor, &spawnError)
            }
        }
        guard pid > 0 else { throw LocaleEditorError("Cannot start \(executable.lastPathComponent): " + String(cString: strerror(spawnError))) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var code: Int32 = 0
        var completed = false
        while clock.now < deadline {
            let result = le_poll_process(pid, &code)
            if result > 0 { completed = true; break }
            if result < 0 { throw LocaleEditorError("Could not reap \(executable.lastPathComponent): " + String(cString: strerror(errno))) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if !completed {
            // The worker owns its process group, so its unprivileged subprocesses also stop.
            _ = kill(-pid, SIGTERM)
            let grace = clock.now.advanced(by: .milliseconds(250))
            while clock.now < grace {
                let result = le_poll_process(pid, &code)
                if result != 0 { completed = true; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            if !completed {
                if kill(-pid, SIGKILL) == 0 || errno == ESRCH {
                    let killDeadline = clock.now.advanced(by: .seconds(1))
                    while clock.now < killDeadline {
                        if le_poll_process(pid, &code) != 0 { completed = true; break }
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    if !completed { DispatchQueue.global().async { _ = le_reap_process(pid) } }
                }
                else {
                    // An elevated helper may no longer be signalable by its caller.
                    // Reap it when it finishes, without blocking the editor indefinitely.
                    DispatchQueue.global().async { _ = le_reap_process(pid) }
                    throw LocaleEditorError("\(executable.lastPathComponent) timed out; the administrator operation may still be running. Check its result before retrying.")
                }
            }
            throw LocaleEditorError("\(executable.lastPathComponent) exceeded the \(Int(timeout))-second time limit.")
        }
        status = code
        #else
        let process = Process()
        process.executableURL = executable; process.arguments = arguments; process.environment = environment
        process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        try process.run()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while process.isRunning && clock.now < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning {
            process.terminate()
            let grace = clock.now.advanced(by: .milliseconds(250))
            while process.isRunning && clock.now < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw LocaleEditorError("\(executable.lastPathComponent) exceeded the \(Int(timeout))-second time limit.")
        }
        process.waitUntilExit(); status = process.terminationStatus
        #endif
        let reader = try FileHandle(forReadingFrom: outputURL)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 1_048_576) ?? Data()
        return ProcessResult(status: status, output: String(decoding: data, as: UTF8.self))
    }
}
