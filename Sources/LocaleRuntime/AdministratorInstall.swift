import Foundation
import LocaleCore

/// Desktop authentication belongs to polkit's session agent; the editor never sees a password.
public enum AdministratorInstall {
    public static func arguments(package: URL, select: Bool, replacing: Bool, worker: URL, graphical: Bool) -> [String] {
        (graphical ? ["--disable-internal-agent"] : []) + [worker.path, "--install-system", package.path]
            + (select ? ["--select"] : []) + (replacing ? ["--replace"] : [])
    }
    public static func decode(status: Int32, output: String) throws -> InstallOutcome? {
        if status == 126 { return nil }
        guard status == 0 else {
            throw LocaleEditorError("Administrator installation was not authorized or could not finish. Ensure a polkit authentication agent is running.\n" + output)
        }
        return try JSONDecoder().decode(InstallOutcome.self, from: Data(output.utf8))
    }
    public static func install(package: URL, select: Bool, replacing: Bool, worker: URL) throws -> InstallOutcome? {
        let pkexec = URL(fileURLWithPath: "/usr/bin/pkexec")
        guard FileManager.default.isExecutableFile(atPath: pkexec.path) else { throw LocaleEditorError("Install pkexec and a polkit authentication agent to install system-wide.") }
        let result = try ProcessRunner.run(pkexec, arguments: arguments(package: package, select: select, replacing: replacing, worker: worker, graphical: true), timeout: 300)
        return try decode(status: result.status, output: result.output)
    }
}
