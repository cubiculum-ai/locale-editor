import Foundation

extension LocaleCategory {
    public var explanation: [String] {
        switch self {
        case .address:
            return ["Postal-address layout: street/house-number order, postcode/city order and line breaks.",
                    "Also contains country and language identifiers; it does not store your personal address.",
                    "Example: '12 Example Street' versus 'Example Street 12'."]
        case .ctype:
            return ["Character classes: which characters count as letters, digits, spaces or punctuation.",
                    "Also controls upper/lowercase mappings and transliteration conventions.",
                    "Alphabetical sorting is in the separate Sorting section (LC_COLLATE)."]
        case .identification:
            return ["Descriptive metadata about this locale definition: title, language, territory, author/contact, revision and date.",
                    "These are source-document details, not file metadata or information about your computer."]
        case .telephone:
            return ["Telephone display conventions and international calling prefixes.",
                    "The format describes presentation; it does not validate numbers or change dialer behavior."]
        case .messages: return ["Yes/no strings and POSIX response-matching expressions, with compiled glibc samples. Application translations are separate."]
        case .name: return ["Personal-name ordering and salutations such as Mr/Ms; it does not store your name. No universal ISO name-order convention is imposed."]
        default: return []
        }
    }
}
