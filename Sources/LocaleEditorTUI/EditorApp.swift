import Foundation
import LocaleCore
import LocaleRuntime

final class EditorApp {
    let terminal: Terminal
    let catalog: LocaleCatalog
    let worker: URL
    var session: EditorSession
    var preferences: EditorPreferences
    var projectURL: URL?
    private var lastFileDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var categoryIndex = 0
    var fieldIndex = 0
    private var fieldOffset = 0
    private var fieldCapacity = 1
    var fieldsFocused = false
    var message = "Click sections / fields · Wheel scrolls lists · Tab switches panels · F4 custom text"
    var words = ["zebra", "Örebro", "apple", "Ängel", "ångström", "Apple", "aachen", "ábaco", "ch", "cz"]
    var category: LocaleCategory { LocaleCategory.allCases[categoryIndex] }
    var fields: [FieldDefinition] {
        if category == .ctype {
            return [.init("character_profile", "Character profile", .text, "Choose a complete Unicode/classification/case/transliteration profile; tables stay inherited."),
                    .init("character_sample", "Test characters", .text, "Edit the sample to inspect compiled glibc character classes, case maps and ASCII transliteration.")]
        }
        return (category == .paper ? [FieldDefinition("paper_size", "Paper size", .text, "Choose a named size; width and height change together. glibc stores whole millimetres.")] : []) + FieldSchema.fields(for: category)
    }
    private var presetIndex: LocalePresetIndex?
    private var snapshot: CompiledPreview?
    private var previewedProject: LocaleProject?
    private var report: PreviewReport?
    private var formatSamples: [String: String] = [:]
    private var dateSamples: [String: String] = [:]
    private var previewError: String?
    private var behavior: BehaviorReport?
    private var characterSample = BehaviorRequest().characters

    init(project: LocaleProject, projectURL: URL?, catalog: LocaleCatalog, worker: URL, cursorMode: CursorMode? = nil) throws {
        self.catalog = catalog; self.worker = worker
        self.session = EditorSession(project: project); self.projectURL = projectURL
        if let projectURL { lastFileDirectory = projectURL.deletingLastPathComponent() }
        self.preferences = EditorPreferences.load()
        if let cursorMode { preferences.cursorMode = cursorMode }
        self.terminal = try Terminal()
        let changed = try catalog.changedSources(for: project)
        if !changed.isEmpty { message = "Source data changed: " + changed.joined(separator: ", ") + ". Review examples before saving." }
    }

    private var lastMenu = 0
    private var hasSelectedField: Bool { fieldIndex > 0 && fieldIndex <= fields.count }
    private func menus() -> [AppMenu] {
        EditorMenus.make(MenuAvailability(fieldSelected: hasSelectedField, canUndo: session.canUndo,
            canRedo: session.canRedo, canPreview: report != nil && previewError == nil, canCompile: LocaleRuntime.supportsGlibc))
    }
    private func openMenu(_ heading: Int? = nil) -> EditorCommand? {
        let result = terminal.menu(menus(), initial: heading ?? lastMenu)
        lastMenu = result.heading
        return result.command
    }

    func run() {
        var redraw = true, size = ""
        while true {
            if previewedProject != session.project { refreshExamples() }
            let newSize = "\(TerminalGeometry.columns)x\(TerminalGeometry.rows)"
            if redraw || size != newSize { render(); size = newSize }
            let key = terminal.key(); redraw = key != .tick
            do {
                var command: EditorCommand?
                switch key {
                case .quit, .text("q"), .function(10): command = .quit
                case .tab, .backTab: fieldsFocused.toggle()
                case .left, .right: if preferences.cursorMode == .legacy { fieldsFocused.toggle() }
                case .up:
                    if fieldsFocused { fieldIndex = max(0, fieldIndex - 1) }
                    else { selectCategory(max(0, categoryIndex - 1)) }
                case .down:
                    if fieldsFocused { fieldIndex = min(fields.count, fieldIndex + 1) }
                    else { selectCategory(min(LocaleCategory.allCases.count - 1, categoryIndex + 1)) }
                case .home: if fieldsFocused { fieldIndex = 0 } else { selectCategory(0) }
                case .end: if fieldsFocused { fieldIndex = fields.count } else { selectCategory(LocaleCategory.allCases.count - 1) }
                case .pageUp: if fieldsFocused { fieldIndex = max(0, fieldIndex - 5) }
                case .pageDown: if fieldsFocused { fieldIndex = min(fields.count, fieldIndex + 5) }
                case .enter:
                    if !fieldsFocused { fieldsFocused = true }
                    else { command = fieldIndex == 0 ? .inherit : .choosePreset }
                case .function(4): command = hasSelectedField ? .customValue : .inherit
                case .text("i"), .text("/"), .function(6): command = .inherit
                case .function(7): command = fieldsFocused && hasSelectedField ? .choosePreset : .inherit
                case .text("r"), .function(8): if fieldsFocused { command = .reset }
                case .text("u"): command = .undo
                case .text("y"): command = .redo
                case .text("s"), .function(2): command = .save
                case .text("o"): command = .open
                case .text("n"): command = .rename
                case .text("e"): command = .export
                case .text("b"): command = .compile
                case .text("a"): command = .finish
                case .text("p"), .function(5): command = .preview
                case .text("v"), .function(3): command = .viewSource
                case .text("w"): command = .sortingWords
                case .function(9): command = openMenu()
                case .alt(let letter):
                    if let index = menus().firstIndex(where: { $0.label.mnemonic == letter }) { command = openMenu(index) }
                case .text("?"), .function(1): command = .help
                case .mouse(let event):
                    if case .menuHeading(let index) = terminal.click(at: event) { command = openMenu(index) }
                    else { try handleMouse(event) }
                default: break
                }
                if let command, try execute(command) { return }
            } catch {
                message = error.localizedDescription.components(separatedBy: .newlines).first ?? "Operation failed."
                terminal.page("Operation could not be completed", lines: error.localizedDescription.components(separatedBy: .newlines))
            }
        }
    }

    /// Menus, function keys and single-key shortcuts share this execution path.
    private func execute(_ command: EditorCommand) throws -> Bool {
        switch command {
        case .quit: return confirmDiscard()
        case .selectSection:
            if let title = terminal.choose("Select section", names: LocaleCategory.allCases.map(\.title), initial: category.title),
               let index = LocaleCategory.allCases.firstIndex(where: { $0.title == title }) {
                fieldsFocused = false; selectCategory(index)
            }
        case .inherit: try chooseSource()
        case .choosePreset: if hasSelectedField { try chooseField() }
        case .customValue: if hasSelectedField { try customField() }
        case .reset:
            if category == .ctype { message = "Character tables follow the selected profile; F6 changes the profile."; break }
            if hasSelectedField {
                if fields[fieldIndex - 1].key == "paper_size" { try session.reset(.paper, keys: ["width", "height"]) }
                else { try session.reset(category, key: fields[fieldIndex - 1].key) }
                message = "Restored inherited value."
            }
        case .undo: session.undo(); message = "Undo."
        case .redo: session.redo(); message = "Redo."
        case .save: try save()
        case .saveAs: try save(asNew: true)
        case .open: try open()
        case .rename:
            if let name = terminal.prompt("Locale name", initial: session.project.name) { try session.rename(name) }
        case .export: try export()
        case .compile: try compile()
        case .preview: try preview()
        case .viewSource: terminal.page("Generated localedef source", lines: try LocaleExporter.render(session.project, catalog: catalog).components(separatedBy: "\n"))
        case .sortingWords:
            if let input = terminal.prompt("Sorting preview words", initial: words.joined(separator: " | "), help: "Separate words with |.") {
                words = input.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                previewedProject = nil
            }
        case .cursorOptions: try options()
        case .help: help()
        case .license: terminal.page("Unicode data license", lines: CurrencySymbols.license.components(separatedBy: "\n"))
        case .install: try installLocale()
        case .international: try applyInternational()
        case .finish: try finishLocale()
        }
        return false
    }

    private func selectCategory(_ index: Int) {
        categoryIndex = index; fieldIndex = 0; fieldOffset = 0
    }
    private func handleMouse(_ event: MouseEvent) throws {
        if case .wheel(let direction) = event.kind {
            switch terminal.scroll(at: event) {
            case .sections:
                fieldsFocused = false
                selectCategory(min(LocaleCategory.allCases.count - 1, max(0, categoryIndex + direction * 3)))
            case .fields where !fields.isEmpty:
                fieldsFocused = true
                fieldOffset = min(max(0, fields.count - fieldCapacity), max(0, fieldOffset + direction * 3))
                fieldIndex = min(min(fields.count, fieldOffset + fieldCapacity), max(fieldOffset + 1, fieldIndex))
            default: break
            }
            return
        }
        switch terminal.click(at: event) {
        case .section(let index): fieldsFocused = false; selectCategory(index)
        case .source: fieldsFocused = true; fieldIndex = 0; try chooseSource()
        case .field(let index) where fields.indices.contains(index):
            fieldsFocused = true; fieldIndex = index + 1; try chooseField()
        default: break
        }
    }

    private func refreshExamples() {
        previewedProject = session.project
        report = nil; behavior = nil; formatSamples = [:]; dateSamples = [:]; snapshot = nil; previewError = "Updating formatted examples…"
        render()
        do {
            let current = try CompiledPreview(project: session.project, catalog: catalog, worker: worker)
            report = try current.report(words: words)
            let values = try catalog.effectiveValues(.time, project: session.project)
            let formats = FieldSchema.fields(for: .time).filter { $0.kind == .format }.compactMap { field -> String? in
                if case .text(let value) = values[field.key] { return value }; return nil
            }
            formatSamples = try current.formatExamples(formats)
            if case .text(let dateFormat) = values["date_fmt"] { dateSamples = try current.formatExamples([dateFormat], gnuDate: true) }
            snapshot = current; previewError = nil
            try refreshBehavior()
        } catch { previewError = error.localizedDescription }
    }

    private func example(_ field: FieldDefinition, values: [String: FieldValue]) -> String {
        if category == .ctype {
            return field.key == "character_profile" ? "Upper: " + (behavior?.uppercase ?? "Requires Linux/glibc") : "ASCII: " + (behavior?.transliteration ?? "Requires Linux/glibc")
        }
        if category == .messages, let behavior, case .text(let text) = values[field.key] {
            if field.key.hasSuffix("expr") { return behavior.example(pattern: text) }
            let yes = behavior.matchedResponses(for: values["yesexpr"]?.display ?? "").contains { $0.utf8.elementsEqual(text.utf8) }
            let no = behavior.matchedResponses(for: values["noexpr"]?.display ?? "").contains { $0.utf8.elementsEqual(text.utf8) }
            return text + " → " + (yes && no ? "ambiguous: matches both" : yes ? "accepted as yes" : no ? "accepted as no" : "not matched by either expression")
        }
        if field.kind == .format, case .text(let format) = values[field.key] {
            return (field.key == "date_fmt" ? dateSamples[format] : formatSamples[format]) ?? (previewError == nil ? "(not specified)" : "Example unavailable — see status")
        }
        if let report {
            if category == .time && ["first_weekday", "first_workday"].contains(field.key) {
                let label = field.key == "first_workday" ? "First workday (offset from week base)" : "First weekday (offset from week base)"
                if let text = report.items.first(where: { $0.label == label })?.value, let day = Int(text),
                   case .strings(let days) = values["day"], days.indices.contains(day - 1) { return days[day - 1] }
            }
            let wanted: String?
            switch category {
            case .numeric: wanted = "Number 1234567.89"
            case .monetary:
                wanted = field.key.hasPrefix("int_") ? "International currency 1234567.89" : field.key.hasPrefix("n_") || field.key == "negative_sign" ? "Currency -1234.5" : "Currency 1234567.89"
            default: wanted = nil
            }
            if let wanted, let result = report.items.first(where: { $0.label == wanted }) { return result.value }
        }
        return FieldExamples.example(field, category: category, values: values)
    }

    private func render() {
        var screen = Screen()
        guard screen.width >= 69, screen.height >= 22 else {
            terminal.draw(["Linux Locale Editor", "Resize to at least 70 columns × 22 rows.", "q: quit"]); return
        }
        screen.menuBar(menus())
        screen.write("LINUX LOCALE EDITOR  " + session.project.name + (session.isDirty ? "  [modified]" : ""), x: 1, y: 1, ink: .bright)
        let left = 24, panelHeight = screen.height - 8, right = screen.width - left
        screen.box(x: 0, y: 2, width: left, height: panelHeight, title: "Sections")
        screen.box(x: left, y: 2, width: right, height: panelHeight, title: category.title)
        screen.scrollTarget(.sections, x: 1, y: 3, width: left - 2, height: panelHeight - 2)
        screen.scrollTarget(.fields, x: left + 1, y: 3, width: right - 2, height: panelHeight - 2)
        for (index, cat) in LocaleCategory.allCases.enumerated() where index < panelHeight - 2 {
            let dirty = !(session.project.sections[cat.rawValue]?.overrides.isEmpty ?? true)
            let ink: Ink = index == categoryIndex ? (fieldsFocused ? .selectedInactive : .selected) : .panel
            screen.write((index == categoryIndex ? "> " : "  ") + cat.title + (dirty ? " *" : ""), x: 1, y: index + 3, width: left - 2, ink: ink)
            screen.clickTarget(.section(index), x: 1, y: index + 3, width: left - 2)
        }
        let selection = try? session.project.selection(category)
        let values = (try? catalog.effectiveValues(category, project: session.project)) ?? [:]
        let contentX = left + 2, contentWidth = right - 4
        screen.write((fieldsFocused && fieldIndex == 0 ? "> " : "  ") + "Inherit: " + (selection?.source ?? "missing"), x: contentX, y: 3, width: contentWidth, ink: fieldsFocused && fieldIndex == 0 ? .selected : .bright)
        screen.clickTarget(.source, x: contentX, y: 3, width: contentWidth)
        screen.write("Definition  →  formatted example", x: contentX, y: 4, width: contentWidth, ink: .accent)
        let visible = max(1, (panelHeight - 5) / 2)
        fieldCapacity = visible
        fieldIndex = min(fieldIndex, fields.count)
        fieldOffset = min(fieldOffset, max(0, fields.count - visible))
        if fieldIndex == 0 { fieldOffset = 0 }
        else if fieldIndex - 1 < fieldOffset { fieldOffset = fieldIndex - 1 }
        else if fieldIndex > fieldOffset + visible { fieldOffset = fieldIndex - visible }
        let offset = fieldOffset
        for index in offset..<min(fields.count, offset + visible) {
            let field = fields[index], y = 5 + (index - offset) * 2
            let value = field.key == "character_profile" ? FieldValue.text(selection?.source ?? "") : field.key == "character_sample" ? .text(characterSample) : field.key == "paper_size" ? FieldValue.text(PaperSizes.name(values: values)) : values[field.key]
            let ink: Ink = fieldsFocused && fieldIndex == index + 1 ? .selected : .panel
            let modified = field.key == "paper_size" ? selection?.overrides["width"] != nil || selection?.overrides["height"] != nil : selection?.overrides[field.key] != nil
            let marker = modified ? "* " : "  "
            screen.write(marker + field.label + ": " + (value?.display.isEmpty == true ? "(empty)" : value?.display ?? "(not specified)"), x: contentX, y: y, width: contentWidth, ink: ink)
            screen.write("  → " + example(field, values: values), x: contentX, y: y + 1, width: contentWidth, ink: .accent)
            screen.clickTarget(.field(index), x: contentX, y: y, width: contentWidth, height: 2)
        }
        if fields.isEmpty {
            var information = category.explanation + ["This section inherits its complete definition.", "F6 selects another source locale."]
            if let selectedSource = selection?.source, let definition = try? catalog.resolve(selectedSource, category: category) {
                let keys = category == .address ? ["postal_fmt", "country_name"] : category == .identification ? ["title", "language", "territory", "revision", "date"] : []
                for key in keys {
                    if let entry = definition.entry(key) {
                        information.append(key + ": " + ((try? SourceSyntax.unquote(entry.value, escape: definition.escape)) ?? entry.value))
                    }
                }
            }
            let wrapped = information.flatMap { Screen.wrapped($0, width: contentWidth) }
            for (index, line) in wrapped.enumerated() where index < panelHeight - 5 {
                screen.write(line, x: contentX, y: 6 + index, width: contentWidth)
            }
            if category == .collate {
                screen.write("Sorted example:", x: contentX, y: 10, width: contentWidth, ink: .accent)
                screen.write(report?.sortedWords.joined(separator: " · ") ?? "Example unavailable", x: contentX, y: 11, width: contentWidth)
            }
        }
        if category == .ctype, let behavior {
            screen.write("glibc simple case maps · ASCII//TRANSLIT:", x: contentX, y: 10, width: contentWidth, ink: .accent)
            screen.write("Lower: " + behavior.lowercase, x: contentX, y: 11, width: contentWidth)
            screen.write("ASCII: " + behavior.transliteration, x: contentX, y: 12, width: contentWidth)
            screen.write("Enter Test characters for the full class table.", x: contentX, y: 13, width: contentWidth)
        }
        let footer = screen.height - 6
        if fieldsFocused && fieldIndex > 0 && fieldIndex <= fields.count {
            let field = fields[fieldIndex - 1]
            let definition = field.key == "character_profile" ? "Complete LC_CTYPE profile: " + (selection?.source ?? "") : field.key == "character_sample" ? "Test sample (not saved in the locale): " + characterSample : field.key == "paper_size" ? "Paper size: " + PaperSizes.name(values: values) : field.key + " = " + (values[field.key]?.source ?? "(not specified)")
            screen.write(definition, x: 1, y: footer, width: screen.width - 2, ink: .bright)
            screen.write("→ " + example(field, values: values), x: 1, y: footer + 1, width: screen.width - 2, ink: .accent)
            screen.write(field.help.isEmpty ? "Enter: predefined values · F4: Custom · F8: inherit again" : field.help, x: 1, y: footer + 2, width: screen.width - 2)
        } else {
            screen.write("Sample: Tuesday 27 Oct 2026, 17:04:05 UTC · 1,234,567.89", x: 1, y: footer, width: screen.width - 2, ink: .accent)
            screen.write("Tab / Shift-Tab switches panels · Enter selects · F4 custom text", x: 1, y: footer + 1, width: screen.width - 2)
            screen.write("a: Export / compile / activate · Locale menu: International conventions · * override", x: 1, y: footer + 2, width: screen.width - 2)
        }
        screen.write(previewError ?? (category == .telephone ? "Examples: glibc definitions · illustrative phone components" : category == .address ? "Examples: glibc definitions · illustrative postal components" : "Examples: glibc · refreshed automatically after edits"), x: 0, y: screen.height - 3, ink: .status)
        screen.write(message, x: 0, y: screen.height - 2, ink: .status)
        screen.functionBar(["Help", "Save", "Source", "Edit", "Preview", "Inherit", "Search", "Reset", "Menu", "Quit"])
        terminal.present(screen)
    }

    private func chooseSource() throws {
        if category == .ctype { try chooseCharacterProfile(); return }
        let choices = SectionProfiles.choices(category, catalog: catalog).map {
            PopupChoice(id: $0.source, label: $0.label, example: $0.source, detail: $0.note)
        }
        let initial = category == .collate && choices.contains(where: { $0.id == "iso14651_t1" }) ? "iso14651_t1" : try session.project.selection(category).source
        if let name = terminal.choose("Inherit " + category.title, choices: choices, initial: initial, subtitle: "Type to search; existing field overrides are retained.") {
            try session.inherit(category, from: name, catalog: catalog)
            message = "\(category.title) inherits from \(name); explicit overrides retained."
        }
    }
    private func chooseField() throws {
        let field = fields[fieldIndex - 1]
        if category == .ctype { if field.key == "character_profile" { try chooseCharacterProfile() } else { try testCharacters() }; return }
        if field.key == "paper_size" { try choosePaperSize(); return }
        let values = try catalog.effectiveValues(category, project: session.project)
        if presetIndex == nil {
            message = "Indexing definitions from all locale sources…"; render()
            presetIndex = LocalePresetIndex(catalog: catalog)
            message = "Predefined field values loaded."
        }
        let presets = presetIndex!.presets(for: category, field: field.key)
        let conventions = InternationalConventions.presets(category: category, field: field.key, values: values)
        var samples: [String: String] = [:]
        if field.kind == .format, let snapshot {
            samples = try snapshot.formatExamples((presets.map(\.value) + conventions.map(\.value)).compactMap { if case .text(let text) = $0 { text } else { nil } }, gnuDate: field.key == "date_fmt")
        }
        let responseExamples = category == .messages && field.key.hasSuffix("expr") ? try snapshot?.behaviorExamples(BehaviorRequest(patterns: presets.map { $0.value.display })) : nil
        var choices: [PopupChoice] = [], mapped: [String: FieldValue] = [:]
        func sample(_ value: FieldValue) -> String {
            if let responseExamples { return responseExamples.example(pattern: value.display) }
            if field.kind == .format, case .text(let format) = value { return samples[format] ?? formatSamples[format] ?? "Requires glibc preview" }
            var edited = values; edited[field.key] = value
            if field.key == "currency_symbol", case .text(let next) = value, case .text(let old) = values[field.key], !old.isEmpty,
               let actual = report?.items.first(where: { $0.label == "Currency 1234567.89" })?.value {
                return actual.replacingOccurrences(of: old, with: next)
            }
            return FieldExamples.example(field, category: category, values: edited)
        }
        for preset in conventions {
            mapped[preset.value.source] = preset.value
            var candidate = values
            candidate.merge(preset.related) { _, new in new }; candidate[field.key] = preset.value
            let definition = preset.value.display.isEmpty ? "(empty)" : preset.value.display
            let label = field.key == "currency_symbol" ? preset.label : definition + "  " + preset.label
            choices.append(PopupChoice(id: preset.value.source, label: label,
                                       example: field.kind == .format ? sample(preset.value) : FieldExamples.example(field, category: category, values: candidate), detail: preset.note))
        }
        if category == .telephone && field.key == "tel_int_fmt" {
            for preset in TelephoneFormats.international {
                let value = FieldValue.text(preset.format)
                if mapped[value.source] != nil { continue }
                mapped[value.source] = value
                choices.append(PopupChoice(id: value.source, label: preset.name + "  " + preset.format, example: sample(value), detail: preset.note))
            }
        }
        if field.key == "currency_symbol" {
            for symbol in CurrencySymbols.all {
                let value = FieldValue.text(symbol.symbol)
                if mapped[value.source] != nil { continue }
                mapped[value.source] = value
                choices.append(PopupChoice(id: value.source, label: symbol.symbol + "  " + symbol.id + "  " + symbol.name, example: sample(value), detail: "Unicode " + CurrencySymbols.unicodeVersion + " · Currency_Symbol (Sc)"))
            }
        }
        for preset in presets {
            let provenance = preset.sources.prefix(8).joined(separator: ", ") + (preset.sources.count > 8 ? " +\(preset.sources.count - 8) more" : "")
            if let index = choices.firstIndex(where: { $0.id == preset.id }) {
                choices[index].detail += " · " + provenance
                continue
            }
            mapped[preset.id] = preset.value
            let label = field.kind == .format ? preset.value.display : preset.value.source
            choices.append(PopupChoice(id: preset.id, label: label.isEmpty ? "(empty)" : label, example: sample(preset.value), detail: "Used by " + provenance))
        }
        if let current = values[field.key], mapped[current.source] == nil {
            mapped[current.source] = current
            choices.append(PopupChoice(id: current.source, label: current.display, example: sample(current), detail: "Current value"))
        }
        choices.append(PopupChoice(id: "__custom__", label: "Custom…", example: "Type your own value", detail: field.help))
        if category == .address && field.key == "postal_fmt" {
            for index in choices.indices {
                var address = values
                if let value = mapped[choices[index].id] { address[field.key] = value }
                choices[index].previewLines = PostalAddresses.lines(values: address)
            }
        }
        let subtitle = field.kind == .format ? "Distinct definitions · \(field.key == "date_fmt" ? "GNU date" : "glibc") examples in active locale · 27 Oct 2026, 17:04 UTC" : "Distinct definitions · candidate samples; applied values are verified by glibc"
        guard let selected = terminal.choose(field.label, choices: choices, initial: conventions.first?.value.source ?? values[field.key]?.source ?? "", subtitle: subtitle) else { return }
        if selected == "__custom__" { try customField(); return }
        if let value = mapped[selected] {
            var changes = conventions.first { $0.value.source == selected }?.related ?? [:]
            changes[field.key] = value
            try session.set(category, values: changes); message = "Selected \(field.label)."
        }
    }
    private func customField() throws {
        let field = fields[fieldIndex - 1]
        if category == .ctype { if field.key == "character_profile" { try chooseCharacterProfile() } else { try testCharacters() }; return }
        if field.key == "paper_size" { try customPaperSize(); return }
        let values = try catalog.effectiveValues(category, project: session.project)
        let initial = values[field.key]?.display ?? ""
        let sample: (String) -> String = { input in
            do {
                let value = try field.parseInput(input)
                if self.category == .messages && field.key.hasSuffix("expr"), let snapshot = self.snapshot {
                    return try snapshot.behaviorExamples(BehaviorRequest(patterns: [input])).example(pattern: input)
                }
                if field.kind == .format, let snapshot = self.snapshot { return try snapshot.formatExamples([input], gnuDate: field.key == "date_fmt")[input] ?? "(empty)" }
                if field.kind == .format { return "Formatted examples require Linux/glibc." }
                var edited = values; edited[field.key] = value
                if self.category == .address && field.key == "postal_fmt" { return PostalAddresses.lines(values: edited).joined(separator: "\n") }
                return FieldExamples.example(field, category: self.category, values: edited)
            } catch { return error.localizedDescription }
        }
        let postal = category == .address && field.key == "postal_fmt"
        if let input = terminal.prompt("Custom: " + field.label, initial: initial, help: field.help, exampleTitle: postal ? "Illustrative postal address" : field.kind == .format ? "Example · 27 Oct 2026, 17:04:05 UTC" : "Illustrative example · applied settings use glibc", multilineExample: postal, example: sample) {
            if category == .messages, field.key.hasSuffix("expr"), let snapshot,
               let error = try snapshot.behaviorExamples(BehaviorRequest(patterns: [input])).error(for: input) {
                throw LocaleEditorError("Invalid POSIX expression: " + error)
            }
            try session.set(category, key: field.key, value: field.parseInput(input))
            message = "Updated \(field.label)."
        }
    }
    private func choosePaperSize() throws {
        let values = try catalog.effectiveValues(.paper, project: session.project)
        var initial = "__custom__"
        if case .integer(let width) = values["width"], case .integer(let height) = values["height"] { initial = PaperSizes.match(width: width, height: height)?.id ?? initial }
        let choices = PaperSizes.all.map { PopupChoice(id: $0.id, label: $0.choiceLabel, example: $0.dimensions, detail: $0.note) }
            + [PopupChoice(id: "__custom__", label: "Custom…", example: "Set width and height", detail: "Whole millimetres, 1–10000; both values are saved as one edit.")]
        guard let selected = terminal.choose("Paper size", choices: choices, initial: "a4", subtitle: "Named sizes · Current: " + initial + " · ISO first · fax-safe = A4 width, no taller than Letter") else { return }
        if selected == "__custom__" { try customPaperSize(); return }
        if let size = PaperSizes.all.first(where: { $0.id == selected }) {
            try session.set(.paper, values: size.overrides)
            message = "Selected " + size.name + " — " + size.dimensions
        }
    }
    private func customPaperSize() throws {
        let values = try catalog.effectiveValues(.paper, project: session.project)
        guard let width = terminal.prompt("Custom paper width (mm)", initial: values["width"]?.display ?? "210", help: "Whole millimetres; both dimensions are applied together."),
              let height = terminal.prompt("Custom paper height (mm)", initial: values["height"]?.display ?? "297", help: "Whole millimetres; Cancel leaves both dimensions unchanged.") else { return }
        try session.set(.paper, values: ["width": FieldSchema.field(.paper, "width")!.parseInput(width), "height": FieldSchema.field(.paper, "height")!.parseInput(height)])
        message = "Updated custom paper size."
    }
    private func options() throws {
        let choices = [PopupChoice(id: "standard", label: "Standard cursor behavior", example: "Tab / Shift-Tab switches panels", detail: "Arrows navigate lists and text; Left/Right do not switch panels."),
                       PopupChoice(id: "legacy", label: "Legacy cursor behavior", example: "Left / Right also switches panels", detail: "Retains the first version's pane-switching shortcuts.")]
        if let choice = terminal.choose("Options · Cursor behavior", choices: choices, initial: preferences.cursorMode.rawValue), let mode = CursorMode(rawValue: choice) {
            preferences.cursorMode = mode
            try preferences.save()
            message = "Saved cursor mode: " + mode.rawValue
        }
    }
    private func confirmDiscard() -> Bool { !session.isDirty || terminal.prompt("Discard unsaved changes? Type yes to continue.") == "yes" }
    private func mayWrite(_ url: URL) -> Bool { !FileBrowser.existsIncludingSymlink(url) || terminal.confirmReplacement(url) }
    private func chooseFile(_ mode: FileDialogMode, initial: URL) throws -> URL? {
        guard let url = try terminal.fileDialog(mode: mode, initial: initial) else { return nil }
        lastFileDirectory = url.deletingLastPathComponent()
        return url
    }
    private func save(asNew: Bool = false) throws {
        let url: URL
        if !asNew, let existing = projectURL { url = existing }
        else {
            let initial = projectURL ?? lastFileDirectory.appendingPathComponent(session.project.name + ".locale-project.json")
            guard let selected = try chooseFile(.save, initial: initial) else { return }
            url = selected
        }
        guard (!asNew && url == projectURL) || mayWrite(url) else { return }
        try session.save(to: url, catalog: catalog); projectURL = url
        // Fingerprint bookkeeping does not change the compiled locale.
        if previewedProject?.sections == session.project.sections { previewedProject = session.project }
        message = "Saved " + url.path
    }
    private func open() throws {
        guard confirmDiscard(), let url = try chooseFile(.open, initial: projectURL ?? lastFileDirectory) else { return }
        let project = try LocaleProject.load(from: url)
        let changed = try catalog.changedSources(for: project)
        session = EditorSession(project: project); projectURL = url; categoryIndex = 0; fieldIndex = 0
        presetIndex = nil
        message = changed.isEmpty ? "Opened " + url.path : "Source data changed: " + changed.joined(separator: ", ")
    }
    private func export() throws {
        let source = try LocaleExporter.render(session.project, catalog: catalog)
        guard let url = try chooseFile(.export, initial: lastFileDirectory.appendingPathComponent(session.project.name + ".src")) else { return }
        guard mayWrite(url) else { return }
        try source.write(to: url, atomically: true, encoding: .utf8); message = "Exported " + url.path
    }
    private func compile() throws {
        guard let url = try chooseFile(.compile, initial: lastFileDirectory.appendingPathComponent("locale-output")) else { return }
        message = "Compiling…"; render()
        let diagnostics = try LocaleRuntime.compile(session.project, catalog: catalog, into: url)
        terminal.page("Compiled successfully", lines: [url.appendingPathComponent(session.project.name).path, "", "Use this directory as LOCPATH and the project name as LC_ALL.", diagnostics])
        message = "Compiled " + session.project.name
    }
    private func preview() throws {
        if let previewError { throw LocaleEditorError(previewError) }
        guard let report else { throw LocaleEditorError("No compiled preview available.") }
        var lines = [report.engine, ""] + report.items.map { $0.label + ": " + $0.value }
        if let behavior {
            lines += ["", "Character handling:", "Upper: " + behavior.uppercase, "Lower: " + behavior.lowercase, "ASCII: " + behavior.transliteration]
            let values = try catalog.effectiveValues(.messages, project: session.project)
            lines += ["", "Yes/no response examples:"] + ["yesexpr", "noexpr"].map { $0 + ": " + behavior.example(pattern: values[$0]?.display ?? "") }
        }
        lines += ["", "Sorting:"] + report.sortedWords.map { "  " + $0 }
        lines += ["", "Postal address example (illustrative components):"] + PostalAddresses.lines(values: try catalog.effectiveValues(.address, project: session.project))
        if !report.diagnostics.isEmpty { lines += ["", report.diagnostics] }
        terminal.page("Preview: " + session.project.name, lines: lines)
    }
    private func help() {
        terminal.page("Keyboard reference", lines: [
            "Up/Down: select a section or field. Tab / Shift-Tab: switch panels.",
            "Home/End: beginning/end of list or text. PgUp/PgDn: scroll lists.",
            "Mouse: click sections, fields, source rows, choices and function keys.",
            "Wheel scrolls the list under the pointer; popup clicks do not reach the panels behind it.",
            "In text dialogs, click to position the cursor; click OK / Cancel to finish.",
            "Enter: choose a unique predefined value. F4: Custom text editing.",
            "F1 Help · F2 Save · F3 Source · F4 Edit · F5 Preview",
            "F6 Inherit · F7 Search · F8 Reset · F9 Menu · F10 Quit",
            "F9 opens the top menu. Left/Right switches menus; Up/Down selects commands.",
            "Alt+L/F/E/O/H opens Locale/File/Edit/Options/Help. Enter or an underlined letter runs a command.",
            "Esc/F9/F10 or a click outside closes a menu without activating the panel below.",
            "Escape followed by 1–9 or 0 also invokes F1–F10.",
            "s save · o open · n rename · e export · b build · u undo · y redo",
            "a: Export / compile / activate. Installation compiles and includes editable project + source.",
            "Locale → International conventions applies ISO dates, Monday, A4, SI and international phones in one undoable edit.",
            "Standards appear first; Unicode generic currency ¤ is a separate preference, not an ISO currency unit.",
            "Names: editable layout/salutations. Yes/no: POSIX regex with glibc matching samples.",
            "Character handling: choose a complete profile, then test classes, simple case maps and ASCII transliteration.",
            "i or / choose section source · r reset · p preview · w sorting words",
            "", "Examples update automatically after changing a parent or value.",
            "Date/time choices are rendered by glibc using the current locale.",
            "Other candidate examples are illustrative; applied settings use compiled glibc output.",
            "Currency: all Unicode 18 Sc symbols, locale currency strings, and Custom.",
            "Popup search matches definitions, examples, Unicode names and source locales.",
            "Options → Cursor behavior selects standard/legacy navigation and remembers it.",
            "File dialogs: Tab directory/list/name; Enter navigates or accepts; F6 Up, F7 MkDir, F8 Hidden.",
            "Click directories to enter and files to select. F2 or the Open/Save/Export button accepts.",
            "Paper size names set both dimensions in one edit. Fax-safe is 210 × 279 mm (whole-mm locale storage).",
            "Telephone: +%c(%a)%l is a display layout; compact international dialing uses +%c%a%l.",
            "Address formats describe postal layouts. Character handling means classes, case maps and transliteration.",
            "Metadata describes the locale source (title, language, territory, author, revision, date).",
            "Locale → Install and select… compiles/verifies first, then offers per-user or system scope.",
            "Per-user activation applies to future shell/user-service sessions; existing processes keep their environment.",
            "Text editing: arrows, Home/End, Backspace/Delete, Ctrl-U clear, Ctrl-W delete word.",
            "List fields use |; grouping uses semicolons; overrides survive parent changes.",
            "Compilation and authoritative examples require glibc Linux.",
        ])
    }

    private func refreshBehavior() throws {
        guard let snapshot else { return }
        let messages = try catalog.effectiveValues(.messages, project: session.project)
        let patterns = ["yesexpr", "noexpr"].compactMap { messages[$0]?.display }
        var seen: Set<String> = []
        let responses = (BehaviorRequest().responses + ["yesstr", "nostr"].compactMap { messages[$0]?.display }).filter { seen.insert(SourceSyntax.quote($0)).inserted }
        behavior = try snapshot.behaviorExamples(BehaviorRequest(patterns: patterns, responses: responses, characters: characterSample))
    }

    private func chooseCharacterProfile() throws {
        let choices = SectionProfiles.choices(.ctype, catalog: catalog).map {
            PopupChoice(id: $0.source, label: $0.label, example: $0.source, detail: $0.note)
        }
        if let source = terminal.choose("Character handling · profile", choices: choices, initial: "i18n", subtitle: "Choose a full profile · compiled samples update after selection") {
            try session.inherit(.ctype, from: source, catalog: catalog)
            message = "Character profile: " + source
        }
    }

    private func testCharacters() throws {
        guard let input = terminal.prompt("Test characters", initial: characterSample,
            help: "Up to 256 Unicode scalars; samples are not stored in your locale.") else { return }
        _ = try FieldDefinition("sample", "Test characters").parseInput(input)
        guard input.unicodeScalars.count <= 256 else { throw LocaleEditorError("Use at most 256 Unicode scalars.") }
        characterSample = input
        try refreshBehavior()
        guard let behavior else { throw LocaleEditorError("Character examples require Linux/glibc.") }
        terminal.page("Character behavior · compiled glibc", lines: ["Profile: " + (try session.project.selection(.ctype).source),
            "Uppercase: " + behavior.uppercase, "Lowercase: " + behavior.lowercase, "ASCII transliteration: " + behavior.transliteration,
            "", "Simple one-character case mappings; not full Unicode case folding or normalization.", ""] + behavior.characters.map { $0.label + ": " + $0.value })
    }

    private func applyInternational() throws {
        terminal.page("International conventions · scope", lines: InternationalConventions.explanation.flatMap { Screen.wrapped($0, width: max(20, TerminalGeometry.columns - 6)) })
        let choices = [PopupChoice(id: "generic", label: "International conventions + generic currency ¤", example: "Preserve language; use ¤", detail: "ISO dates, Monday, A4, SI metric/space grouping, compact international telephone format; keep the ISO currency code."),
                       PopupChoice(id: "currency", label: "International conventions; keep currency", example: "Preserve language and currency", detail: "Apply matching grouping to numbers and money; keep the currency symbol and code."),
                       PopupChoice(id: "cancel", label: "Cancel", example: "Return to editing")]
        guard let choice = terminal.choose("Apply international conventions", choices: choices, initial: "generic", columnTitles: ("Convention set", "Effect")), choice != "cancel" else { return }
        try session.set(InternationalConventions.changes(project: session.project, catalog: catalog, genericCurrency: choice == "generic"))
        message = "Applied international conventions. Language preserved; Undo restores all changed fields."
    }

    private func finishLocale() throws {
        let choices = [PopupChoice(id: "activate", label: "Compile, install and activate…", example: "Personal or system-wide", detail: "Choose scope and review changes. Includes source and editable project. Defaults to personal; system scope authenticates with sudo."),
                       PopupChoice(id: "install", label: "Compile and install only…", example: "Personal or system-wide", detail: "Make the locale available without selecting it as the default."),
                       PopupChoice(id: "compile", label: "Compile to a directory…", example: "Portable output / LOCPATH", detail: "Create a compiled locale under a chosen directory; never changes defaults."),
                       PopupChoice(id: "export", label: "Export locale source…", example: "Save a localedef source file", detail: "Choose a filename; no compilation or activation.")]
        guard let action = terminal.choose("Export / compile / activate locale", choices: choices, initial: LocaleRuntime.supportsGlibc ? "activate" : "export", columnTitles: ("Action", "Destination")) else { return }
        switch action {
        case "activate": try installLocale(initialAction: "select")
        case "install": try installLocale(initialAction: "only")
        case "compile": try compile()
        default: try export()
        }
    }

    private func installLocale(initialAction: String = "select") throws {
        guard LocaleRuntime.supportsGlibc else { throw LocaleEditorError("Installation requires glibc Linux.") }
        let scopes = [PopupChoice(id: "user", label: "Current user", example: "No administrator privileges", detail: "Default: install in your data directory; selection updates your shell/user-service configuration."),
                      PopupChoice(id: "system", label: "System-wide", example: "Administrator privileges required", detail: "Install for all users; selection changes system defaults for future sessions.")]
        guard let selectedScope = terminal.choose("Install locale · scope", choices: scopes, initial: "user", columnTitles: ("Scope", "Access")), let scope = InstallScope(rawValue: selectedScope) else { return }
        let actions = [PopupChoice(id: "select", label: "Install and select", example: "Use as the default for this scope", detail: "Set LANG and clear category overrides; already-running programs keep their environment."),
                       PopupChoice(id: "only", label: "Install only", example: "Keep current defaults", detail: "Make the locale available without activating it.")]
        guard let action = terminal.choose("Install locale · activation", choices: actions, initial: initialAction, columnTitles: ("Action", "Effect")) else { return }
        let select = action == "select"
        let locations = scope == .user ? InstallLocations.user() : InstallLocations.system()
        let replacing = try LocaleInstaller.checkDestination(name: session.project.name, locations: locations, replacing: true)
        let writes = select ? try LocaleSelection.plan(name: session.project.name, locations: locations) : []
        message = "Compiling and verifying installation package…"; render()
        let prepared = try PreparedLocaleInstall(project: session.project, catalog: catalog, worker: worker)
        var review = ["Locale: " + session.project.name, "Scope: " + (scope == .user ? "Current user" : "System-wide"),
                      "Destination: " + locations.locales.appendingPathComponent(session.project.name).path,
                      replacing ? "Replace the previous app-owned build; preserve a backup." : "Create a new locale; existing unrelated locales are protected.", ""]
        if select {
            review += ["Selection files:"] + writes.map { "  " + $0.path.path }
            review += ["", "Selection takes effect in future login/shell sessions or user services.", "Existing terminals and applications cannot have their parent environment changed by this app."]
            if scope == .user { review += ["Per-user selection uses LOCPATH. Archive-only locales may need separate generation for programs that explicitly select them."] }
            else { review += ["Per-user locale overrides still take precedence over the system default."] }
        }
        review += ["", "The package has already passed localedef and glibc verification.", "Original selection files and the previous app-owned build will be backed up."]
        if select && scope == .user && locations.profiles.isEmpty { review += ["This shell is not automatically configured. Use activate.sh manually; environment.d is still written for user services."] }
        terminal.page("Review installation", lines: review.flatMap { Screen.wrapped($0, width: max(20, TerminalGeometry.columns - 6)) })
        let confirmation = [PopupChoice(id: "cancel", label: "Cancel", example: "Return to editing"),
                            PopupChoice(id: "install", label: select ? "Install and select" : "Install", example: session.project.name, detail: locations.locales.path)]
        guard terminal.choose("Confirm installation", choices: confirmation, initial: "cancel", columnTitles: ("Action", "Locale")) == "install" else { return }
        let outcome: InstallOutcome
        if scope == .system {
            outcome = try terminal.installSystemPackage(prepared.directory, select: select, replacing: replacing, executable: worker)
        } else {
            outcome = try LocaleInstaller.install(package: prepared.directory, locations: locations, select: select, replacing: replacing, worker: worker)
        }
        var result = ["Installed: " + outcome.destination, "Editable project copy: " + outcome.destination + "/project.json", outcome.selected ? "Selected for future sessions in the chosen scope." : "Defaults were not changed.", "Backups: " + outcome.backupDirectory]
        if let activation = outcome.activationScript { result += ["", "To apply in an existing POSIX-compatible shell:", ". " + LocaleSelection.quote(activation)] }
        terminal.page("Locale installation complete", lines: result.flatMap { Screen.wrapped($0, width: max(20, TerminalGeometry.columns - 6)) })
        message = "Installed " + outcome.name + (outcome.selected ? " and selected for future sessions." : ".")
    }
}
