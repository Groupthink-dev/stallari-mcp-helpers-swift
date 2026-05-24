// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "stallari-mcp-helpers",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MCPHelpers",
            targets: ["MCPHelpers"]
        ),
        .executable(
            name: "stallari-mcp-lint",
            targets: ["stallari-mcp-lint"]
        ),
    ],
    dependencies: [
        // swift-syntax — used by the S-AUD-001 audit-surface honesty lint
        // (DD-338 Phase B Swift). Pinned `from: "600.0.0"` to match the
        // version stallari-harness Tools/source-lint uses (avoids two
        // SwiftSyntax versions being resolved when consumed side-by-side).
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "MCPHelpers",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/MCPHelpers"
        ),
        .executableTarget(
            name: "stallari-mcp-lint",
            dependencies: ["MCPHelpers"],
            path: "Sources/StallariMCPLintCLI"
        ),
        .testTarget(
            name: "MCPHelpersTests",
            dependencies: ["MCPHelpers"],
            path: "Tests/MCPHelpersTests"
        ),
    ]
)
