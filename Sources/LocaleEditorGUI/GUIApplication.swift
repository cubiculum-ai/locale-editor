import Foundation
import Dispatch
import Glibc
import LocaleCore
import LocaleRuntime
import CGtkBridge

private final class IdleTask: @unchecked Sendable {
    let body: @Sendable () -> Void
    init(_ body: @escaping @Sendable () -> Void) { self.body = body }
}
private func idleCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<IdleTask>.fromOpaque(context).takeRetainedValue().body()
}
private func onGTK(_ body: @escaping @Sendable () -> Void) {
    legui_idle(idleCallback, Unmanaged.passRetained(IdleTask(body)).toOpaque())
}
private func eventCallback(_ context: UnsafeMutableRawPointer?, _ action: UnsafePointer<CChar>?, _ index: Int32, _ text: UnsafePointer<CChar>?) {
    guard let context, let action else { return }
    Unmanaged<GUIController>.fromOpaque(context).takeUnretainedValue().event(String(cString: action), index: Int(index), text: text.map(String.init(cString:)) ?? "")
}
private final class JobResult<T>: @unchecked Sendable {
    let result: Result<T, Error>
    init(_ result: Result<T, Error>) { self.result = result }
}
private struct Choice {
    let id: String
    var label: String
    var example: String
    var detail: String
    var changes: [String: FieldValue] = [:]
}
private struct Examples {
    let snapshot: CompiledPreview
    let report: PreviewReport
    let formats: [String: String]
    let dateFormats: [String: String]
    let behavior: BehaviorReport
}

public enum GUIApplication {
    public static func run(project: LocaleProject, projectURL: URL?, catalog: LocaleCatalog, worker: URL) throws {
        let controller = GUIController(project: project, projectURL: projectURL, catalog: catalog, worker: worker)
        controller.initialSourceChanges = try catalog.changedSources(for: project)
        guard let view = legui_create(eventCallback, Unmanaged.passUnretained(controller).toOpaque()) else {
            throw LocaleEditorError("Cannot open a graphical display. Use locale-editor --tui for terminal mode.")
        }
        controller.view = view
        defer { legui_destroy(view) }
        _ = legui_run(view)
        withExtendedLifetime(controller) {}
    }
}

/// GTK calls and editing state live on the GTK thread. A single worker performs bounded
/// compilation/preview/installation work while controls are disabled; results return via idle.
private final class GUIController: @unchecked Sendable {
    var view: OpaquePointer!
    let catalog: LocaleCatalog
    let worker: URL
    var session: EditorSession
    var projectURL: URL?
    var directory: URL
    var categoryIndex = 0
    var selectedField = 0
    var busy = false
    var examples: Examples?
    var previewError: String?
    var initialSourceChanges: [String] = []
    var presetIndex: LocalePresetIndex?
    var promptExample: ((String) -> String)?
    var characters = BehaviorRequest().characters
    var words = ["zebra", "Örebro", "apple", "Ängel", "ångström", "Apple", "aachen", "ábaco"]
    let queue = DispatchQueue(label: "org.linuxlocaleeditor.preview")
    var category: LocaleCategory { LocaleCategory.allCases[categoryIndex] }
    var fields: [FieldDefinition] {
        if category == .ctype {
            return [.init("character_profile", "Character profile", .text, "Select a complete classification, simple case-mapping and transliteration profile."),
                    .init("character_sample", "Test characters", .text, "Inspect up to 256 Unicode scalars. This sample is not stored in the locale.")]
        }
        return (category == .paper ? [.init("paper_size", "Paper size", .text, "Named sizes set width and height together, in whole millimetres.")] : []) + FieldSchema.fields(for: category)
    }
    var field: FieldDefinition? { fields.indices.contains(selectedField) ? fields[selectedField] : nil }

    init(project: LocaleProject, projectURL: URL?, catalog: LocaleCatalog, worker: URL) {
        session = EditorSession(project: project); self.projectURL = projectURL
        self.catalog = catalog; self.worker = worker
        directory = projectURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
    }
    func consume(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }; defer { legui_free(pointer) }; return String(cString: pointer)
    }
    func message(_ title: String, _ text: String) { legui_message(view, title, text) }
    func confirm(_ title: String, _ text: String, accept: String) -> Bool { legui_confirm(view, title, text, accept) != 0 }
    func status(_ text: String) { legui_status(view, text) }
    func prompt(_ title: String, initial: String, help: String = "", example: ((String) -> String)? = nil) -> String? {
        promptExample = example; defer { promptExample = nil }
        return consume(legui_prompt(view, title, initial, help))
    }
    func choose(_ title: String, _ choices: [Choice], initial: String = "", custom: Bool = false) -> String? {
        guard let dialog = legui_choices(view, title, custom ? 1 : 0) else { return nil }
        for item in choices { legui_choice_add(dialog, item.id, item.label, item.example, item.detail) }
        return consume(legui_choice_run(dialog, initial))
    }
    func file(_ mode: Int32, title: String, suggested: String = "") -> URL? {
        let initial = suggested.isEmpty ? directory : directory.appendingPathComponent(suggested)
        guard let path = consume(legui_file(view, mode, title, initial.path)) else { return nil }
        let result = URL(fileURLWithPath: path)
        directory = mode == 2 ? result : result.deletingLastPathComponent()
        return result
    }
    func job<T>(_ title: String, operation: @escaping @Sendable () throws -> T, completion: @escaping @Sendable (Result<T, Error>) -> Void) {
        busy = true; legui_busy(view, 1); status(title)
        queue.async {
            let result = JobResult(Result { try operation() })
            onGTK { [self] in
                busy = false; legui_busy(view, 0)
                completion(result.result)
                legui_history(view, session.canUndo ? 1 : 0, session.canRedo ? 1 : 0)
            }
        }
    }
    func failed(_ error: Error) { status(error.localizedDescription.components(separatedBy: .newlines).first ?? "Operation failed"); message("Operation could not be completed", error.localizedDescription) }

    func event(_ action: String, index: Int, text: String) {
        if action == "input-preview" { legui_prompt_example(view, promptExample?(text) ?? ""); return }
        if busy { if action == "quit" { status("Please finish the current operation or cancel its authentication dialog before closing.") }; return }
        do {
            switch action {
            case "ready":
                for item in LocaleCategory.allCases { legui_section_add(view, item.title) }
                legui_section_select(view, 0); refresh()
            case "section": if LocaleCategory.allCases.indices.contains(index) { categoryIndex = index; selectedField = 0; render() }
            case "field": selectedField = index; legui_help(view, field?.help ?? "This section inherits a complete profile.")
            case "preset": try preset()
            case "custom": try custom()
            case "inherit": try inherit()
            case "reset":
                guard let field else { return }
                if category == .ctype { if field.key == "character_sample" { characters = BehaviorRequest().characters; refresh() } else { try inherit() }; return }
                try session.reset(category, keys: field.key == "paper_size" ? ["width", "height"] : [field.key]); refresh()
            case "undo": session.undo(); refresh()
            case "redo": session.redo(); refresh()
            case "international": try international()
            case "rename": if let name = prompt("Rename locale", initial: session.project.name, help: "Example: en_US.UTF-8@personal") { try session.rename(name); refresh() }
            case "save": try save(asNew: false)
            case "save-as": try save(asNew: true)
            case "open": try open()
            case "new": try new()
            case "export": try export()
            case "compile": compile()
            case "install": try install()
            case "preview": message("Formatted preview", previewText(full: true))
            case "source": message("Generated localedef source", try LocaleExporter.render(session.project, catalog: catalog))
            case "words": if let value = prompt("Sorting sample", initial: words.joined(separator: " | "), help: "Separate at most 256 words with |.") { let next = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }; guard next.count <= 256 else { throw LocaleEditorError("Use at most 256 words.") }; words = next; refresh() }
            case "quit": if discard() { legui_quit(view) }
            case "license": message("Unicode data license", CurrencySymbols.license)
            case "help": message("Linux Locale Editor", "Native GTK editor for Xfce and other Linux desktops.\n\nChoose a section, then double-click a field for searchable presets. Custom and Reset are available below the field list. Examples are compiled with glibc.\n\nCtrl+N New · Ctrl+O Open · Ctrl+S Save · Ctrl+Shift+S Save As\nCtrl+Z Undo · Ctrl+Shift+Z Redo · F4 Custom · F7 Presets · F8 Reset\nF5 Preview · F3 Source · Ctrl+Q Quit\n\nEdit → International conventions preserves your language while applying international formats.\nFile → Install and select offers personal and system-wide scope. System installation uses the desktop's polkit administrator dialog.\n\nInstalled locales affect applications that consult glibc. Character tables and sorting rules are selected as complete inherited profiles.")
            default: break
            }
        } catch { failed(error) }
    }

    func refresh() {
        examples = nil; previewError = nil; render()
        let project = session.project, catalog = catalog, worker = worker, words = words, characters = characters
        job("Compiling formatted examples…", operation: {
            let snapshot = try CompiledPreview(project: project, catalog: catalog, worker: worker)
            let time = try catalog.effectiveValues(.time, project: project)
            let formats = FieldSchema.fields(for: .time).filter { $0.kind == .format }.compactMap { time[$0.key]?.display }
            let messages = try catalog.effectiveValues(.messages, project: project)
            var seen: Set<String> = []
            let responses = (BehaviorRequest().responses + ["yesstr", "nostr"].compactMap { messages[$0]?.display }).filter { seen.insert(SourceSyntax.quote($0)).inserted }
            return try Examples(snapshot: snapshot, report: snapshot.report(words: words), formats: snapshot.formatExamples(formats),
                dateFormats: snapshot.formatExamples([time["date_fmt"]?.display ?? ""], gnuDate: true),
                behavior: snapshot.behaviorExamples(BehaviorRequest(patterns: ["yesexpr", "noexpr"].compactMap { messages[$0]?.display }, responses: responses, characters: characters)))
        }, completion: { [self] result in
            switch result {
            case .success(let result): examples = result; status("Examples verified by glibc · changes are saved only when you choose Save or Install.")
            case .failure(let error): previewError = error.localizedDescription; status("Preview unavailable — edit the values or view the diagnostic below.")
            }
            render()
            if !initialSourceChanges.isEmpty {
                let changed = initialSourceChanges; initialSourceChanges = []
                message("Source definitions changed", "Review the compiled examples before saving. Changed sources:\n" + changed.joined(separator: "\n"))
            }
        })
    }
    func example(_ field: FieldDefinition, values: [String: FieldValue]) -> String {
        if category == .ctype { return field.key == "character_profile" ? "Upper: " + (examples?.behavior.uppercase ?? "Updating…") : "ASCII: " + (examples?.behavior.transliteration ?? "Updating…") }
        if field.kind == .format { return (field.key == "date_fmt" ? examples?.dateFormats : examples?.formats)?[values[field.key]?.display ?? ""] ?? "Example unavailable" }
        if category == .messages, let behavior = examples?.behavior {
            if field.key.hasSuffix("expr") { return behavior.example(pattern: values[field.key]?.display ?? "") }
            let value = values[field.key]?.display ?? ""
            let yes = behavior.matchedResponses(for: values["yesexpr"]?.display ?? "").contains { $0.utf8.elementsEqual(value.utf8) }
            let no = behavior.matchedResponses(for: values["noexpr"]?.display ?? "").contains { $0.utf8.elementsEqual(value.utf8) }
            return yes && no ? "Ambiguous: matches both responses" : yes ? "Accepted as yes" : no ? "Accepted as no" : "Not matched by either expression"
        }
        let actual = category == .numeric ? "Number 1234567.89" : category == .monetary ? (field.key.hasPrefix("int_") ? "International currency 1234567.89" : field.key.hasPrefix("n_") || field.key == "negative_sign" ? "Currency -1234.5" : "Currency 1234567.89") : nil
        if let actual, let item = examples?.report.items.first(where: { $0.label == actual }) { return item.value }
        return FieldExamples.example(field, category: category, values: values)
    }
    func render() {
        legui_title(view, session.project.name + (session.isDirty ? " *" : "") + " — Linux Locale Editor")
        let selection = try? session.project.selection(category)
        let values: [String: FieldValue] = FieldSchema.fields(for: category).isEmpty ? [:] : ((try? catalog.effectiveValues(category, project: session.project)) ?? [:])
        legui_heading(view, category.title, "Inherits from: " + (selection?.source ?? ""), category.explanation.joined(separator: " "))
        legui_fields_clear(view)
        for field in fields {
            let value = field.key == "paper_size" ? PaperSizes.name(values: values) : field.key == "character_profile" ? selection?.source ?? "" : field.key == "character_sample" ? characters : values[field.key]?.display ?? "(not specified)"
            let explicit = field.key == "paper_size" ? selection?.overrides["width"] != nil || selection?.overrides["height"] != nil : selection?.overrides[field.key] != nil
            legui_field_add(view, field.label, value.isEmpty ? "(empty)" : value, example(field, values: values), explicit ? "Custom override" : "Inherited")
        }
        selectedField = min(max(0, selectedField), fields.count - 1)
        legui_field_select(view, Int32(selectedField)); legui_help(view, field?.help ?? "Use Change inheritance to select a complete profile.")
        legui_examples(view, previewText(full: false)); legui_history(view, session.canUndo ? 1 : 0, session.canRedo ? 1 : 0)
    }
    func previewText(full: Bool) -> String {
        if let previewError { return previewError }
        guard let examples else { return "Updating compiled examples…" }
        let values: [String: FieldValue] = FieldSchema.fields(for: category).isEmpty ? [:] : ((try? catalog.effectiveValues(category, project: session.project)) ?? [:])
        if full {
            return ([examples.report.engine, ""] + examples.report.items.map { $0.label + ": " + $0.value }
                + ["", "Sorted: " + examples.report.sortedWords.joined(separator: " · "), "Uppercase: " + examples.behavior.uppercase, "Lowercase: " + examples.behavior.lowercase, "ASCII: " + examples.behavior.transliteration, examples.report.diagnostics]).joined(separator: "\n")
        }
        switch category {
        case .ctype: return (["Upper: " + examples.behavior.uppercase, "Lower: " + examples.behavior.lowercase, "ASCII: " + examples.behavior.transliteration, "Simple case maps; not full Unicode case folding.", ""] + examples.behavior.characters.map { $0.label + ": " + $0.value }).joined(separator: "\n")
        case .collate: return "Compiled glibc sorting:\n" + examples.report.sortedWords.joined(separator: " · ") + "\n\nView → Sorting words changes this sample."
        case .address: return "Illustrative postal address:\n" + PostalAddresses.lines(values: values).joined(separator: "\n")
        case .name: return "Illustrative name:\n" + PersonalNames.sample("name_fmt", values: values)
        case .numeric, .monetary: return examples.report.items.filter { category == .numeric ? $0.label.hasPrefix("Number ") : $0.label.contains("urrency ") }.map { $0.label + ": " + $0.value }.joined(separator: "\n")
        case .time: return examples.report.items.filter { $0.label.hasPrefix("2026-") || $0.label.hasPrefix("2027-") }.map { $0.label + ": " + $0.value }.joined(separator: "\n")
        default: return fields.map { $0.label + ": " + example($0, values: values) }.joined(separator: "\n")
        }
    }
    func inherit() throws {
        let choices = SectionProfiles.choices(category, catalog: catalog).map { Choice(id: $0.source, label: $0.label, example: $0.source, detail: $0.note) }
        let initial = category == .ctype ? "i18n" : category == .collate ? "iso14651_t1" : try session.project.selection(category).source
        if let value = choose("Inherit " + category.title, choices, initial: initial) { try session.inherit(category, from: value, catalog: catalog); refresh() }
    }
    func preset() throws {
        guard let field else { try inherit(); return }
        if category == .ctype { if field.key == "character_profile" { try inherit() } else { try custom() }; return }
        if field.key == "paper_size" {
            let choices = PaperSizes.all.map { Choice(id: $0.id, label: $0.choiceLabel, example: $0.dimensions, detail: $0.note, changes: $0.overrides) }
            guard let id = choose("Paper size", choices, initial: "a4", custom: true) else { return }
            if id == "__custom__" { try custom(); return }
            if let choice = choices.first(where: { $0.id == id }) { try session.set(.paper, values: choice.changes); refresh() }; return
        }
        let category = category, values = try catalog.effectiveValues(category, project: session.project), snapshot = examples?.snapshot
        job("Preparing presets and formatted samples…", operation: { [self] in
            if presetIndex == nil { presetIndex = LocalePresetIndex(catalog: catalog) }
            let presets = presetIndex!.presets(for: category, field: field.key)
            let conventions = InternationalConventions.presets(category: category, field: field.key, values: values)
            let formats = (presets.map(\.value) + conventions.map(\.value)).map(\.display)
            let samples = field.kind == .format ? try snapshot?.formatExamples(formats, gnuDate: field.key == "date_fmt") : nil
            let responses = category == .messages && field.key.hasSuffix("expr") ? try snapshot?.behaviorExamples(BehaviorRequest(patterns: formats)) : nil
            var choices: [Choice] = [], used: Set<String> = []
            func add(_ value: FieldValue, label: String, detail: String, related: [String: FieldValue] = [:]) {
                guard used.insert(value.source).inserted else { return }
                var changes = related; changes[field.key] = value
                var candidate = values; candidate.merge(changes) { _, new in new }
                let sample = samples?[value.display] ?? responses?.example(pattern: value.display) ?? (category == .address && field.key == "postal_fmt" ? PostalAddresses.lines(values: candidate).joined(separator: "\n") : FieldExamples.example(field, category: category, values: candidate))
                choices.append(Choice(id: value.source, label: label, example: sample, detail: detail, changes: changes))
            }
            for preset in conventions { add(preset.value, label: preset.value.display + " · " + preset.label, detail: preset.note, related: preset.related) }
            if category == .telephone && field.key == "tel_int_fmt" { for preset in TelephoneFormats.international { add(.text(preset.format), label: preset.format + " · " + preset.name, detail: preset.note) } }
            if field.key == "currency_symbol" { for symbol in CurrencySymbols.all { add(.text(symbol.symbol), label: symbol.symbol + " " + symbol.id + " " + symbol.name, detail: "Unicode " + CurrencySymbols.unicodeVersion) } }
            for preset in presets { add(preset.value, label: preset.value.display.isEmpty ? "(empty)" : preset.value.display, detail: "Used by " + preset.sources.joined(separator: ", ")) }
            if let current = values[field.key] { add(current, label: current.display, detail: "Current value") }
            return choices
        }, completion: { [self] result in
            do {
                let choices = try result.get()
                status("Choose a preset or use Custom.")
                let initial = InternationalConventions.presets(category: category, field: field.key, values: values).first?.value.source ?? values[field.key]?.source ?? ""
                guard let id = choose(field.label, choices, initial: initial, custom: true) else { return }
                if id == "__custom__" { try custom(); return }
                if let choice = choices.first(where: { $0.id == id }) { try session.set(category, values: choice.changes); refresh() }
            } catch { failed(error) }
        })
    }
    func custom() throws {
        guard let field else { return }
        if category == .ctype {
            if field.key == "character_profile" { try inherit(); return }
            guard let value = prompt("Test characters", initial: characters, help: field.help) else { return }
            _ = try FieldDefinition("sample", "Sample").parseInput(value)
            guard value.unicodeScalars.count <= 256 else { throw LocaleEditorError("Use at most 256 Unicode scalars.") }
            characters = value; refresh(); return
        }
        let values = try catalog.effectiveValues(category, project: session.project)
        if field.key == "paper_size" {
            guard let width = prompt("Paper width (mm)", initial: values["width"]?.display ?? "210"),
                  let height = prompt("Paper height (mm)", initial: values["height"]?.display ?? "297") else { return }
            try session.set(.paper, values: ["width": FieldSchema.field(.paper, "width")!.parseInput(width), "height": FieldSchema.field(.paper, "height")!.parseInput(height)]); refresh(); return
        }
        let example: (String) -> String = { [self] input in
            do {
                let value = try field.parseInput(input)
                if field.kind == .format { return try examples?.snapshot.formatExamples([input], gnuDate: field.key == "date_fmt")[input] ?? "Requires a valid compiled preview" }
                if category == .messages && field.key.hasSuffix("expr") { return try examples?.snapshot.behaviorExamples(BehaviorRequest(patterns: [input])).example(pattern: input) ?? "Requires a valid compiled preview" }
                var changed = values; changed[field.key] = value
                if category == .address && field.key == "postal_fmt" { return PostalAddresses.lines(values: changed).joined(separator: "\n") }
                return FieldExamples.example(field, category: category, values: changed)
            } catch { return error.localizedDescription }
        }
        guard let value = prompt("Custom: " + field.label, initial: values[field.key]?.display ?? "", help: field.help, example: example) else { return }
        if category == .messages, field.key.hasSuffix("expr"), let error = try examples?.snapshot.behaviorExamples(BehaviorRequest(patterns: [value])).error(for: value) { throw LocaleEditorError("Invalid POSIX expression: " + error) }
        try session.set(category, key: field.key, value: field.parseInput(value)); refresh()
    }
    func international() throws {
        let choices = [Choice(id: "generic", label: "International conventions + generic currency ¤", example: "Preserve language; use ¤", detail: InternationalConventions.explanation.joined(separator: "\n")),
                       Choice(id: "currency", label: "International conventions; keep currency", example: "Preserve language and currency", detail: InternationalConventions.explanation.joined(separator: "\n"))]
        guard let choice = choose("Apply international conventions", choices, initial: "generic") else { return }
        try session.set(InternationalConventions.changes(project: session.project, catalog: catalog, genericCurrency: choice == "generic")); refresh()
    }
    func discard() -> Bool { !session.isDirty || confirm("Unsaved changes", "Discard the unsaved changes to " + session.project.name + "?", accept: "_Discard changes") }
    func save(asNew: Bool) throws {
        guard let url = asNew || projectURL == nil ? file(1, title: "Save locale project", suggested: session.project.name + ".locale-project.json") : projectURL else { return }
        try session.save(to: url, catalog: catalog); projectURL = url; render(); status("Saved " + url.path)
    }
    func open() throws {
        guard discard(), let url = file(0, title: "Open locale project") else { return }
        let project = try LocaleProject.load(from: url)
        let changed = try catalog.changedSources(for: project)
        session = EditorSession(project: project); projectURL = url; selectedField = 0
        if !changed.isEmpty { message("Source definitions changed", "Review the compiled examples before saving. Changed sources:\n" + changed.joined(separator: "\n")) }
        refresh()
    }
    func new() throws {
        guard discard() else { return }
        let choices = catalog.names.map { Choice(id: $0, label: $0, example: "Base locale", detail: "Each section can inherit a different source after creation.") }
        guard let base = choose("New locale · base", choices, initial: "en_US"), let name = prompt("New locale name", initial: base + ".UTF-8@personal") else { return }
        session = EditorSession(project: try LocaleProject(name: name, base: base)); projectURL = nil; categoryIndex = 0; selectedField = 0; legui_section_select(view, 0); refresh()
    }
    func export() throws {
        let source = try LocaleExporter.render(session.project, catalog: catalog)
        guard let url = file(1, title: "Export localedef source", suggested: session.project.name + ".src") else { return }
        try source.write(to: url, atomically: true, encoding: .utf8); status("Exported " + url.path)
    }
    func compile() {
        guard let root = file(2, title: "Choose compiled locale output directory") else { return }
        let project = session.project, catalog = catalog
        job("Compiling locale…", operation: { try LocaleRuntime.compile(project, catalog: catalog, into: root) }, completion: { [self] result in
            do { let diagnostics = try result.get(); message("Locale compiled", root.appendingPathComponent(project.name).path + "\n\nUse " + root.path + " as LOCPATH. Defaults have not been changed.\n" + diagnostics); status("Compiled " + project.name) } catch { failed(error) }
        })
    }
    func install() throws {
        let scopes = [Choice(id: "user", label: "Current user", example: "No administrator privileges", detail: "Install under your XDG data directory. Default scope."),
                      Choice(id: "system", label: "System-wide", example: "Administrator authentication", detail: "Install for all users. The desktop's polkit agent handles authentication.")]
        guard let scopeName = choose("Install locale · scope", scopes, initial: "user"), let scope = InstallScope(rawValue: scopeName) else { return }
        let actions = [Choice(id: "select", label: "Install and select", example: "Use as the default for this scope", detail: "Applies to future sessions. Already-running applications keep their environment."),
                       Choice(id: "only", label: "Install only", example: "Preserve existing defaults", detail: "Make the locale available without changing login defaults.")]
        guard let action = choose("Install locale · activation", actions, initial: "select") else { return }
        let select = action == "select", locations = scope == .user ? InstallLocations.user() : InstallLocations.system()
        let project = session.project, catalog = catalog, worker = worker
        job("Compiling and verifying the installation package…", operation: {
            let replacing = try LocaleInstaller.checkDestination(name: project.name, locations: locations, replacing: true)
            let writes = select ? try LocaleSelection.plan(name: project.name, locations: locations) : []
            return (try PreparedLocaleInstall(project: project, catalog: catalog, worker: worker), replacing, writes.map { $0.path.path })
        }, completion: { [self] result in
            do {
                let (prepared, replacing, writes) = try result.get()
                var lines = ["Locale: " + project.name, "Scope: " + (scope == .user ? "Current user" : "System-wide"), "Destination: " + locations.locales.appendingPathComponent(project.name).path,
                    replacing ? "Replace the previous app-owned build; preserve a backup." : "Install a new locale.", select ? "Select for future sessions." : "Preserve current defaults.", "", "The package passed localedef and glibc verification."]
                if select { lines += ["", "Configuration files:"] + writes; lines += ["", "Existing terminals and applications retain their current environment."] }
                if scope == .user && select { lines += ["Per-user selection uses LOCPATH; archive-only locales may need separate generation for applications explicitly selecting them."] }
                if scope == .system { lines += ["The desktop will request administrator authentication. Per-user overrides still take precedence."] }
                guard confirm("Review locale installation", lines.joined(separator: "\n"), accept: select ? "_Install and select" : "_Install") else { status("Installation cancelled."); return }
                job("Installing locale" + (scope == .system ? " — complete the administrator authentication dialog…" : "…"), operation: {
                    if scope == .system && geteuid() != 0 { return try AdministratorInstall.install(package: prepared.directory, select: select, replacing: replacing, worker: worker) }
                    return try LocaleInstaller.install(package: prepared.directory, locations: locations, select: select, replacing: replacing, worker: worker) as InstallOutcome?
                }, completion: { [self] result in
                    do {
                        guard let outcome = try result.get() else { status("Administrator authentication cancelled. Your edits are preserved."); return }
                        var lines = ["Installed: " + outcome.destination, "Editable project: " + outcome.destination + "/project.json", "Backups: " + outcome.backupDirectory, outcome.selected ? "Selected for future sessions." : "Existing defaults were preserved."]
                        if let activation = outcome.activationScript { lines += ["", "To apply to an existing POSIX-compatible shell:", ". " + LocaleSelection.quote(activation)] }
                        message("Locale installation complete", lines.joined(separator: "\n")); status("Installed " + outcome.name)
                    } catch { failed(error) }
                })
            } catch { failed(error) }
        })
    }
}
