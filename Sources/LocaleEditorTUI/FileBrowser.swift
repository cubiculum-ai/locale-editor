import Foundation
import LocaleCore

enum FileDialogMode: Equatable {
    case open, save, export, compile
    var title: String { switch self { case .open: "Open project"; case .save: "Save project as"; case .export: "Export localedef source"; case .compile: "Compile locale · output directory" } }
    var action: String { self == .open ? "Open" : self == .save ? "Save" : self == .compile ? "Compile" : "Export" }
}

struct BrowserEntry {
    let url: URL
    let name: String
    let directory: Bool
    let symbolicLink: Bool
    let size: Int64?
    var displayName: String {
        let safe = name.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t")
        return (directory ? "/ " : symbolicLink ? "@ " : "  ") + safe
    }
}

/// Filesystem browsing is separate from terminal rendering and never opens or writes a project.
struct FileBrowser {
    private(set) var directory: URL
    private(set) var entries: [BrowserEntry] = []
    private(set) var showHidden = false

    init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        try navigate(to: directory)
    }

    func resolve(_ path: String) throws -> URL {
        guard !path.utf8.contains(0) else { throw LocaleEditorError("A path cannot contain NUL.") }
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return directory.appendingPathComponent(expanded).standardizedFileURL
    }

    mutating func navigate(to url: URL) throws {
        let target = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocaleEditorError("Not a directory: " + target.path)
        }
        // Foundation on Darwin can reject enumeration at a symlink itself. Enumerate the
        // resolved directory, then retain the visible path for navigation and selections.
        let contents = try FileManager.default.contentsOfDirectory(at: target.resolvingSymlinksInPath(), includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey], options: [])
        var result: [BrowserEntry] = []
        let parent = target.deletingLastPathComponent()
        if parent.path != target.path { result.append(BrowserEntry(url: parent, name: "..", directory: true, symbolicLink: false, size: nil)) }
        var listed: [BrowserEntry] = []
        for actualFile in contents where showHidden || !actualFile.lastPathComponent.hasPrefix(".") {
            let file = target.appendingPathComponent(actualFile.lastPathComponent)
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            listed.append(BrowserEntry(url: file, name: file.lastPathComponent, directory: isDirectory.boolValue,
                symbolicLink: attributes?[.type] as? FileAttributeType == .typeSymbolicLink,
                size: (attributes?[.size] as? NSNumber)?.int64Value))
        }
        listed.sort {
            if $0.directory != $1.directory { return $0.directory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        result += listed
        // Only replace state once listing succeeded, so errors retain the current directory.
        directory = target; entries = result
    }

    mutating func toggleHidden() throws {
        showHidden.toggle()
        do { try navigate(to: directory) } catch { showHidden.toggle(); throw error }
    }

    func destination(_ name: String, mode: FileDialogMode) throws -> URL {
        if mode == .compile {
            let result = try resolve(name.isEmpty ? "." : name)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: result.path, isDirectory: &directory) {
                guard directory.boolValue else { throw LocaleEditorError("Choose a directory for compiled locale output.") }
            } else {
                let parent = result.deletingLastPathComponent()
                guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory), directory.boolValue else {
                    throw LocaleEditorError("Create or choose the parent directory first.")
                }
            }
            return result
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocaleEditorError("Choose a file or enter a filename.") }
        let result = try resolve(name)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: result.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue { return result } // Enter/F2 navigates into directories.
        let resolved = result.resolvingSymlinksInPath()
        if mode == .open {
            guard exists, (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileManager.default.isReadableFile(atPath: resolved.path) else { throw LocaleEditorError("Choose an existing, readable regular file.") }
        } else {
            let parent = result.deletingLastPathComponent()
            var parentIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
                throw LocaleEditorError("The destination directory does not exist: " + parent.path)
            }
            guard FileManager.default.isWritableFile(atPath: parent.path) else { throw LocaleEditorError("The destination directory is not writable.") }
            if exists, (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true {
                throw LocaleEditorError("The destination is not a regular file.")
            }
        }
        return result
    }

    static func existsIncludingSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

/// Shared editing rules for the two path/name fields in a file dialog.
struct FileTextBuffer {
    var characters: [Character]
    var cursor: Int
    var offset = 0
    var text: String { String(characters) }
    init(_ text: String) { characters = Array(text); cursor = characters.count }
    mutating func replace(_ text: String) { self = Self(text) }
    mutating func handle(_ key: Key) {
        switch key {
        case .left: cursor = max(0, cursor - 1)
        case .right: cursor = min(characters.count, cursor + 1)
        case .home: cursor = 0
        case .end: cursor = characters.count
        case .backspace: if cursor > 0 { characters.remove(at: cursor - 1); cursor -= 1 }
        case .delete: if cursor < characters.count { characters.remove(at: cursor) }
        case .clearLine: replace("")
        case .deleteWord:
            while cursor > 0 && characters[cursor - 1].isWhitespace { characters.remove(at: cursor - 1); cursor -= 1 }
            while cursor > 0 && !characters[cursor - 1].isWhitespace { characters.remove(at: cursor - 1); cursor -= 1 }
        case .text(let text):
            if characters.count + text.count <= 8192 { characters.insert(contentsOf: text, at: cursor); cursor += text.count }
        default: break
        }
    }
    mutating func visible(width: Int) -> (text: String, cursorColumn: Int) {
        if cursor < offset { offset = cursor }
        while offset < cursor && Screen.displayWidth(String(characters[offset..<cursor])) >= width - 1 { offset += 1 }
        return (String(characters.dropFirst(offset)), Screen.displayWidth(String(characters[offset..<cursor])))
    }
    mutating func click(column: Int) { cursor = Screen.cursorIndex(in: characters, offset: offset, column: column) }
}
