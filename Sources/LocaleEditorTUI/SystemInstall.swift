import Foundation
import LocaleCore
import LocaleRuntime
import CLocaleBridge
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum AttachedProcess {
    static func run(_ executable: URL, arguments: [String]) throws -> (status: Int32, data: Data, processGroup: Int32) {
        let output = Pipe()
        var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }
        let pid = argv.withUnsafeMutableBufferPointer { le_spawn_attached(executable.path, $0.baseAddress, output.fileHandleForWriting.fileDescriptor) }
        guard pid > 0 else { throw LocaleEditorError("Could not start the administrator tool.") }
        let processGroup = getpgid(pid)
        try output.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        try output.fileHandleForReading.close()
        return (le_wait_attached(pid), data, processGroup)
    }
}

extension Terminal {
    func installSystemPackage(_ package: URL, select: Bool, replacing: Bool, executable: URL) throws -> InstallOutcome {
        if geteuid() == 0 { return try LocaleInstaller.install(package: package, locations: .system(), select: select, replacing: replacing, worker: executable) }
        let usePolkit = FileManager.default.isExecutableFile(atPath: "/usr/bin/pkexec")
        guard let tool = usePolkit ? "/usr/bin/pkexec" : ["/usr/bin/sudo", "/bin/sudo"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw LocaleEditorError("Install pkexec for administrator authentication, or run installation as an administrator.")
        }
        // Credentials belong to polkit's desktop/text agent (or sudo in development), never our UI.
        le_terminal_leave()
        defer { _ = le_terminal_enter() }
        _ = tcflush(STDIN_FILENO, TCIFLUSH)
        let arguments = usePolkit ? AdministratorInstall.arguments(package: package, select: select, replacing: replacing, worker: executable, graphical: false)
            : ["--", executable.path, "--install-system", package.path] + (select ? ["--select"] : []) + (replacing ? ["--replace"] : [])
        let result = try AttachedProcess.run(URL(fileURLWithPath: tool), arguments: arguments)
        if usePolkit && result.status == 126 { throw LocaleEditorError("Administrator authentication cancelled. Your edits are preserved.") }
        guard result.status == 0 else {
            FileHandle.standardOutput.write(Data("\nInstallation did not complete. Press Enter to return to the editor.\n".utf8))
            _ = readLine()
            throw LocaleEditorError("Administrator installation failed (status \(result.status)).")
        }
        return try JSONDecoder().decode(InstallOutcome.self, from: result.data)
    }
}
