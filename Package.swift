// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Separate build graphs keep the terminal package entirely free of GTK libraries.
#if os(Linux)
let withGUI = ProcessInfo.processInfo.environment["LOCALE_EDITOR_GUI"] == "1"
#else
let withGUI = false
#endif
let guiTargets: [Target] = withGUI ? [
    .systemLibrary(name: "CGtk", pkgConfig: "gtk+-3.0", providers: [.apt(["libgtk-3-dev"])]),
    .target(name: "CGtkBridge", dependencies: ["CGtk"]),
    .target(name: "LocaleEditorGUI", dependencies: ["LocaleCore", "LocaleRuntime", "CGtkBridge"]),
] : []

let package = Package(
    name: "LinuxLocaleEditor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LocaleCore", targets: ["LocaleCore"]),
        .library(name: "LocaleRuntime", targets: ["LocaleRuntime"]),
        .executable(name: "locale-editor", targets: ["LocaleEditorTUI"]),
    ],
    targets: [
        .target(name: "LocaleCore"),
        .target(name: "CLocaleBridge"),
        .target(name: "LocaleRuntime", dependencies: ["LocaleCore", "CLocaleBridge"]),
        .executableTarget(name: "LocaleEditorTUI", dependencies: [.byName(name: "LocaleCore"), .byName(name: "LocaleRuntime"), .byName(name: "CLocaleBridge")] + (withGUI ? [.byName(name: "LocaleEditorGUI")] : []), swiftSettings: withGUI ? [.define("LOCALE_EDITOR_GUI")] : []),
        .testTarget(name: "LocaleCoreTests", dependencies: ["LocaleCore"]),
        .testTarget(name: "LocaleRuntimeTests", dependencies: ["LocaleRuntime"]),
        .testTarget(name: "LocaleEditorTUITests", dependencies: ["LocaleEditorTUI"]),
    ] + guiTargets
)
