// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MonkeyClaudeUsage",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Business logic and I/O — no AppKit, unit-testable.
        .target(
            name: "MonkeyClaudeUsageCore",
            path: "Sources/MonkeyClaudeUsageCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Menu bar app: AppKit/SwiftUI shell around the core.
        .executableTarget(
            name: "MonkeyClaudeUsage",
            dependencies: ["MonkeyClaudeUsageCore"],
            path: "Sources/MonkeyClaudeUsage",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MonkeyClaudeUsageTests",
            dependencies: ["MonkeyClaudeUsageCore"],
            path: "Tests/MonkeyClaudeUsageTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
