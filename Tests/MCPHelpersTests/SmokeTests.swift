// Smoke test — verifies the package imports cleanly.
//
// Comprehensive tests for `MetaEnvelope` + `formatMetaLine` + `appendMeta`
// ship in `MetaTests.swift` (Spec A v2 subagent). This file exists to keep
// CI green on the scaffold commit before those land, and as a permanent
// import-smoke guard going forward.

import Testing
@testable import MCPHelpers

@Suite("Package smoke")
struct SmokeTests {
    @Test("MCPHelpers.version matches Package.swift")
    func versionMatchesPackage() {
        #expect(MCPHelpers.version == "0.1.0")
    }
}
