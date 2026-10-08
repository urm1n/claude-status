// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusLight",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared model, hook state machine, settings.json installer. Foundation only.
        .target(name: "StatusCore"),
        // The tiny binary Claude Code runs for every hook event.
        .executableTarget(name: "csl-hook", dependencies: ["StatusCore"]),
        // The menu bar app.
        .executableTarget(name: "ClaudeStatusLight", dependencies: ["StatusCore"]),
        .testTarget(name: "StatusCoreTests", dependencies: ["StatusCore"]),
    ]
)
