import Foundation
import LocaleCore
import LocaleRuntime
#if LOCALE_EDITOR_GUI
import LocaleEditorGUI
#endif
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct Main {
    #if LOCALE_EDITOR_GUI
    static let guiAvailable = true
    #else
    static let guiAvailable = false
    #endif
    static let usage = """
    Linux Locale Editor — a Swift editor for composing UTF-8 glibc locales

    locale-editor [edit] [--sources DIR] [--base en_GB] [--name en_GB.UTF-8@personal]
    locale-editor edit --project FILE [--sources DIR]
    locale-editor list [--sources DIR]
    locale-editor new --base NAME --name NAME --output PROJECT.json [--sources DIR]
    locale-editor export --project FILE --output LOCALE.src [--sources DIR]
    locale-editor preview --project FILE [--words-file WORDS.json] [--sources DIR]
    locale-editor compile --project FILE --output DIRECTORY [--sources DIR]
    locale-editor install --project FILE [--scope user|system] [--select] [--replace] [--sources DIR]

    --sources may be repeated; earlier directories take precedence. System locale sources
    are also available when installed. The default is /usr/share/i18n/locales.
    --force permits replacing an output file for new/export (never compiled directories).
    --cursor-mode standard|legacy overrides the saved preference (Options > Cursor behavior).
    --gui / --tui selects the interface. The GUI package includes both; the TUI package has no GTK dependency.
    Invoking locale-editor-tui or locale-edit-tui selects the terminal interface.
    Compilation/previews require Linux/glibc, localedef, UTF-8 charmaps and locale sources.

    macOS source-editing demo:
      swift run locale-editor --sources Examples/locales --base demo_en

    Inside the TUI: ↑↓ navigate, Tab switch pane, i inherit, Enter edit, r reset,
    p preview, s save, e export, v source, u undo, y redo, F9 menus, ? help, q quit.
    """

    static func main() {
        do { try run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data(("locale-editor: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    static func run(_ arguments: [String]) throws {
        if arguments == ["--version"] { print("Linux Locale Editor 0.2.0 (" + (guiAvailable ? "GTK + TUI" : "TUI only") + ")"); return }
        if arguments.first == "--install-system" {
            guard arguments.count >= 2, arguments.dropFirst(2).allSatisfy({ ["--select", "--replace"].contains($0) }), geteuid() == 0 else {
                throw LocaleEditorError("The system installation helper requires administrator privileges and a prepared package.")
            }
            let result = try LocaleInstaller.install(package: fileURL(arguments[1]), locations: .system(), select: arguments.contains("--select"), replacing: arguments.contains("--replace"), worker: LocaleRuntime.currentExecutable)
            FileHandle.standardOutput.write(try JSONEncoder().encode(result))
            return
        }
        if arguments == ["--license"] { print(CurrencySymbols.license); return }
        if arguments.first == "--behavior-worker" {
            guard arguments.count == 2 else { throw LocaleEditorError("Invalid behavior worker invocation.") }
            let data = try Data(contentsOf: fileURL(arguments[1]))
            guard data.count <= 1_048_576 else { throw LocaleEditorError("Behavior request too large.") }
            let request = try JSONDecoder().decode(BehaviorRequest.self, from: data)
            FileHandle.standardOutput.write(try JSONEncoder().encode(LocaleRuntime.runBehaviorWorker(request)))
            return
        }
        if arguments.first == "--format-worker" || arguments.first == "--date-format-worker" {
            guard arguments.count == 2 else { throw LocaleEditorError("Invalid format worker invocation.") }
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            guard data.count <= 1_048_576 else { throw LocaleEditorError("Format request too large.") }
            let formats = try JSONDecoder().decode([String].self, from: data)
            let result = try arguments.first == "--date-format-worker" ? LocaleRuntime.runDateFormatWorker(formats: formats) : LocaleRuntime.runFormatWorker(formats: formats)
            FileHandle.standardOutput.write(try JSONEncoder().encode(result))
            return
        }
        if arguments.first == "--preview-worker" {
            guard arguments.count == 2 else { throw LocaleEditorError("Invalid preview worker invocation.") }
            let words = try readWords(URL(fileURLWithPath: arguments[1]))
            let report = try LocaleRuntime.runPreviewWorker(words: words)
            FileHandle.standardOutput.write(try JSONEncoder().encode(report))
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") { print(usage); return }
        var command = "edit", options: [String: String] = [:], roots: [URL] = [], force = false, select = false, replace = false, i = 0
        var frontend = FrontendMode.preferred(invocation: CommandLine.arguments[0], guiAvailable: guiAvailable)
        var commandSeen = false
        let validOptions = ["--sources", "--base", "--name", "--project", "--output", "--words-file", "--cursor-mode", "--scope"]
        while i < arguments.count {
            let key = arguments[i]
            if key == "--gui" || key == "--tui" { frontend = key == "--gui" ? .gui : .tui; i += 1; continue }
            if !key.hasPrefix("-"), !commandSeen { command = key; commandSeen = true; i += 1; continue }
            if key == "--force" { force = true; i += 1; continue }
            if key == "--select" { select = true; i += 1; continue }
            if key == "--replace" { replace = true; i += 1; continue }
            guard validOptions.contains(key), i + 1 < arguments.count else { throw LocaleEditorError("Unknown or incomplete option \(key). Use --help.") }
            let value = arguments[i + 1]
            if key == "--sources" { roots.append(fileURL(value)) } else { options[key] = value }
            i += 2
        }
        guard ["edit", "list", "new", "export", "preview", "compile", "install"].contains(command) else { throw LocaleEditorError("Unknown command \(command). Use --help.") }
        if command == "edit" && frontend == .gui && !guiAvailable { throw LocaleEditorError("This is the terminal-only build. Install locale-editor-gui for the graphical interface, or use --tui.") }
        guard command == "install" || (!select && !replace && options["--scope"] == nil) else { throw LocaleEditorError("--scope, --select and --replace apply only to install.") }
        let systemRoot = URL(fileURLWithPath: "/usr/share/i18n/locales")
        if !roots.contains(systemRoot) { roots.append(systemRoot) }
        let catalog = try LocaleCatalog(roots: roots)
        if command == "list" { print(catalog.names.joined(separator: "\n")); return }
        let projectURL = options["--project"].map(fileURL)
        var project: LocaleProject
        if let projectURL { project = try LocaleProject.load(from: projectURL) }
        else {
            guard ["edit", "new"].contains(command) else { throw LocaleEditorError("\(command) requires --project FILE.") }
            let base = options["--base"] ?? (catalog.names.contains("en_GB") ? "en_GB" : catalog.names.contains("demo_en") ? "demo_en" : catalog.names[0])
            _ = try catalog.source(base)
            project = try LocaleProject(name: options["--name"] ?? base + ".UTF-8@personal", base: base)
        }
        let worker = LocaleRuntime.currentExecutable
        switch command {
        case "edit":
            #if LOCALE_EDITOR_GUI
            if frontend == .gui {
                try GUIApplication.run(project: project, projectURL: projectURL, catalog: catalog, worker: worker)
                return
            }
            #endif
            let mode = options["--cursor-mode"].flatMap(CursorMode.init(rawValue:))
            if options["--cursor-mode"] != nil && mode == nil { throw LocaleEditorError("Cursor mode must be standard or legacy.") }
            try EditorApp(project: project, projectURL: projectURL, catalog: catalog, worker: worker, cursorMode: mode).run()
        case "new":
            let url = try outputURL(options, force: force)
            project.sourceFingerprints = try catalog.fingerprints(for: project)
            try project.save(to: url)
            print("Saved " + url.path)
        case "export":
            let source = try LocaleExporter.render(project, catalog: catalog)
            let url = try outputURL(options, force: force)
            try source.write(to: url, atomically: true, encoding: .utf8)
            print("Exported " + url.path)
        case "preview":
            let words = try options["--words-file"].map { try readWords(fileURL($0)) }
            let report = try LocaleRuntime.preview(project, catalog: catalog, worker: worker, words: words ?? ["zebra", "Örebro", "apple", "Ängel", "ångström", "Apple", "ábaco"])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report)); print("")
        case "compile":
            guard let output = options["--output"] else { throw LocaleEditorError("compile requires --output DIRECTORY.") }
            let diagnostics = try LocaleRuntime.compile(project, catalog: catalog, into: fileURL(output))
            print("Compiled " + project.name + " in " + fileURL(output).path)
            if !diagnostics.isEmpty { print(diagnostics) }
        case "install":
            guard let scope = InstallScope(rawValue: options["--scope"] ?? "user") else { throw LocaleEditorError("Scope must be user or system.") }
            if scope == .system && geteuid() != 0 { throw LocaleEditorError("For system installation, use the TUI's Install and select workflow, or run this command as an administrator.") }
            let prepared = try PreparedLocaleInstall(project: project, catalog: catalog, worker: worker)
            let outcome = try LocaleInstaller.install(package: prepared.directory, locations: scope == .user ? .user() : .system(), select: select, replacing: replace, worker: worker)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(outcome)); print("")
        default: break
        }
    }
    private static func fileURL(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
    private static func outputURL(_ options: [String: String], force: Bool) throws -> URL {
        guard let path = options["--output"] else { throw LocaleEditorError("This command requires --output FILE.") }
        let url = fileURL(path)
        guard force || !FileManager.default.fileExists(atPath: url.path) else { throw LocaleEditorError("Output already exists; use --force to replace it.") }
        return url
    }
    private static func readWords(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        guard data.count <= 65536 else { throw LocaleEditorError("Sorting input must be at most 64 KiB.") }
        let words = try JSONDecoder().decode([String].self, from: data)
        guard words.count <= 256, words.allSatisfy({ !$0.utf8.contains(0) }) else { throw LocaleEditorError("Use at most 256 words, without NUL characters.") }
        return words
    }
}
