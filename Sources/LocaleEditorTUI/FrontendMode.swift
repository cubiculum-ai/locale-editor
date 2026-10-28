import Foundation
import LocaleCore

enum FrontendMode: String {
    case gui, tui
    static func preferred(invocation: String, guiAvailable: Bool) -> FrontendMode {
        let name = URL(fileURLWithPath: invocation).lastPathComponent
        return name.hasSuffix("-tui") || !guiAvailable ? .tui : .gui
    }
}
