import Foundation

public struct SectionProfile: Sendable {
    public let source: String
    public let label: String
    public let note: String
}

public enum SectionProfiles {
    public static func choices(_ category: LocaleCategory, catalog: LocaleCatalog) -> [SectionProfile] {
        let preferred = category == .ctype ? ["i18n", "i18n_ctype"] : category == .collate ? ["iso14651_t1"] : []
        let available = catalog.definitionNames(for: category)
        return (preferred + catalog.names.filter { !preferred.contains($0) }).compactMap { name in
            guard available.contains(name) else { return nil }
            let label: String, note: String
            switch (category, name) {
            case (.ctype, "i18n"):
                label = "International character repertoire · Unicode / glibc"
                note = "Unicode-derived glibc classes and simple case maps, with neutral transliteration. This is not full Unicode case folding or normalization."
            case (.ctype, "i18n_ctype"):
                label = "Unicode classes and case maps · no transliteration"
                note = "Classification and simple case mapping from the installed glibc Unicode tables."
            case (.collate, "iso14651_t1"):
                label = "International standard · ISO/IEC 14651 template"
                note = "The host's iso14651_t1 common ordering template, without a language-specific locale's tailoring. Table/version follows installed glibc data, not necessarily the latest ISO edition."
            default:
                label = name
                note = "Complete " + category.rawValue + " section from " + name + ". Compiled examples update after selection."
            }
            return SectionProfile(source: name, label: label, note: note)
        }
    }
}
