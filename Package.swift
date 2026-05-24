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
    ],
    targets: [
        .target(
            name: "MCPHelpers",
            path: "Sources/MCPHelpers"
        ),
        .testTarget(
            name: "MCPHelpersTests",
            dependencies: ["MCPHelpers"],
            path: "Tests/MCPHelpersTests"
        ),
    ]
)
