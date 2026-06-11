// Tests for `MCPHelpers.lint` — S-AUD-001 audit-surface honesty linter
// (DD-338 Phase B Swift sibling).
//
// Each L-numbered case mirrors the spec section in the Python sibling's
// test suite (`stallari-mcp-helpers/tests/test_lint.py`) so the verdict
// behaviour stays in lock-step across languages even when the source
// shape (Swift switch-dispatch vs Python FastMCP decorator) differs.
//
// Tests synthesise a tiny on-disk blade fixture per case under
// `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`,
// run `lintBlade`, and assert the verdict shape + counts. The synthesis
// helpers below mirror the real-world tool-registration patterns we see
// in `apple-notes-blade-mcp` + `apple-mail-blade-mcp` (switch-dispatch
// ToolRegistry + per-tool Handler struct under `Tools/`).

import Foundation
import Testing
@testable import MCPHelpers

// MARK: - Fixture builders

private struct BladeFixture {
    let root: URL
    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stallari-mcp-lint-fixtures")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.root = url
    }
    func write(file: String, _ contents: String) throws -> URL {
        let target = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: target, atomically: true, encoding: .utf8)
        return target
    }
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func catalog(_ blade: String, _ tools: [(name: String, audit: String)]) -> [String: Any] {
    return [
        "name": blade,
        "tools": tools.map { (name, audit) -> [String: Any] in
            [
                "name": name,
                "granularity": ["audit_surface": audit],
            ]
        },
    ]
}

// MARK: - Tests

@Suite("Lint — S-AUD-001 audit-surface honesty")
struct LintTests {

    // L1 — switch-dispatch + handler.handle() calls a blade-local
    // makeResultWithMeta wrapper whose body reaches appendMeta → match.
    // Since v0.4.0 (AUD-04-13) the wrapper is resolved by BODY, not
    // trusted by bare name — the fixture therefore defines it.
    @Test("L1 — switch-dispatch handler calls makeResultWithMeta (structured) → match")
    func l1_switchDispatchStructuredMatch() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let listFolders: ListFoldersHandler = ListFoldersHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_list_folders":
                    return await listFolders.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/ListFoldersHandler.swift", """
        func makeResultWithMeta(payload: Int, meta: Int) -> Int {
            _ = appendMeta("body", "_meta: {}")
            return payload
        }
        struct ListFoldersHandler {
            func handle() async -> Int {
                let payload = 0
                let meta = 0
                return makeResultWithMeta(payload: payload, meta: meta)
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l1", [("blade_list_folders", "structured")])
        )
        let verdict = try #require(result.tools["blade_list_folders"])
        #expect(verdict.auditSurface.result == "match")
        #expect(verdict.auditSurface.actual == "structured")
    }

    // L2 — switch-dispatch + handler returns silently → over-declared
    @Test("L2 — handler does not emit; catalog declares structured → over-declared")
    func l2_overDeclared() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let silent: SilentHandler = SilentHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_silent":
                    return await silent.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/SilentHandler.swift", """
        struct SilentHandler {
            func handle() async -> Int {
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l2", [("blade_silent", "structured")])
        )
        let verdict = try #require(result.tools["blade_silent"])
        #expect(verdict.auditSurface.result == "over-declared")
        #expect(verdict.auditSurface.actual == "minimal")
    }

    // L3 — handler calls appendMeta directly (not via makeResultWithMeta) → match
    @Test("L3 — direct appendMeta call satisfies emission → match")
    func l3_directAppendMeta() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let direct: DirectHandler = DirectHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_direct":
                    return await direct.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/DirectHandler.swift", """
        struct DirectHandler {
            func handle() async -> Int {
                let body = "hi"
                let line = "_meta: {}"
                _ = appendMeta(body, line)
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l3", [("blade_direct", "structured")])
        )
        let verdict = try #require(result.tools["blade_direct"])
        #expect(verdict.auditSurface.result == "match")
    }

    // L4 — handler routes through a custom wrapper that calls appendMeta → match
    @Test("L4 — wrapper-function resolution reaches appendMeta → match")
    func l4_wrapperFunction() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let wrapped: WrappedHandler = WrappedHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_wrapped":
                    return await wrapped.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/WrappedHandler.swift", """
        func myFinaliser(_ payload: String) -> String {
            let line = "_meta: {}"
            return appendMeta(payload, line)
        }
        struct WrappedHandler {
            func handle() async -> Int {
                _ = myFinaliser("body")
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l4", [("blade_wrapped", "structured")])
        )
        let verdict = try #require(result.tools["blade_wrapped"])
        #expect(verdict.auditSurface.result == "match", Comment(rawValue: verdict.auditSurface.detail))
    }

    // L5 — catalog says minimal but handler DOES emit → under-declared
    @Test("L5 — minimal declared but handler emits → under-declared")
    func l5_underDeclared() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let undersold: UndersoldHandler = UndersoldHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_undersold":
                    return await undersold.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/UndersoldHandler.swift", """
        func makeResultWithMeta(payload: Int, meta: Int) -> Int {
            _ = appendMeta("body", "_meta: {}")
            return payload
        }
        struct UndersoldHandler {
            func handle() async -> Int {
                return makeResultWithMeta(payload: 0, meta: 0)
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l5", [("blade_undersold", "minimal")])
        )
        let verdict = try #require(result.tools["blade_undersold"])
        #expect(verdict.auditSurface.result == "under-declared")
    }

    // L6 — minimal declared, no emit → match
    @Test("L6 — minimal declared, handler does not emit → match")
    func l6_minimalMatch() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let plain: PlainHandler = PlainHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_plain":
                    return await plain.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/PlainHandler.swift", """
        struct PlainHandler {
            func handle() async -> Int { return 0 }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l6", [("blade_plain", "minimal")])
        )
        let verdict = try #require(result.tools["blade_plain"])
        #expect(verdict.auditSurface.result == "match")
    }

    // L7 — audit_surface=none → always match regardless of body
    @Test("L7 — audit_surface=none short-circuits to match")
    func l7_noneAlwaysMatch() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let bytes: BytesHandler = BytesHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_bytes":
                    return await bytes.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/BytesHandler.swift", """
        struct BytesHandler {
            func handle() async -> Int { return 0 }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l7", [("blade_bytes", "none")])
        )
        let verdict = try #require(result.tools["blade_bytes"])
        #expect(verdict.auditSurface.result == "match")
        #expect(verdict.auditSurface.actual == "indeterminate")
    }

    // L8 — catalog references a tool with no matching registration → indeterminate
    @Test("L8 — tool not found in source tree → indeterminate")
    func l8_toolNotFound() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let real: RealHandler = RealHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_real":
                    return await real.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/RealHandler.swift", """
        struct RealHandler {
            func handle() async -> Int { return 0 }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l8", [("phantom_tool", "structured")])
        )
        let verdict = try #require(result.tools["phantom_tool"])
        #expect(verdict.auditSurface.result == "indeterminate")
        #expect(verdict.auditSurface.actual == "indeterminate")
        #expect(verdict.auditSurface.detail.contains("no Swift registration matched"))
    }

    // L9 — summary aggregation across mixed verdicts
    @Test("L9 — summary aggregates match/over/under/indeterminate counts")
    func l9_summaryAggregation() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let m: MatchHandler = MatchHandler()
            let o: OverHandler = OverHandler()
            let u: UnderHandler = UnderHandler()
            let mm: MinHandler = MinHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "t_match_struct": return await m.handle()
                case "t_over": return await o.handle()
                case "t_under": return await u.handle()
                case "t_match_min": return await mm.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/Handlers.swift", """
        func makeResultWithMeta(payload: Int, meta: Int) -> Int {
            _ = appendMeta("body", "_meta: {}")
            return payload
        }
        struct MatchHandler {
            func handle() async -> Int { return makeResultWithMeta(payload: 0, meta: 0) }
        }
        struct OverHandler {
            func handle() async -> Int { return 0 }
        }
        struct UnderHandler {
            func handle() async -> Int { return makeResultWithMeta(payload: 0, meta: 0) }
        }
        struct MinHandler {
            func handle() async -> Int { return 0 }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l9", [
                ("t_match_struct", "structured"),
                ("t_over", "structured"),
                ("t_under", "minimal"),
                ("t_match_min", "minimal"),
                ("phantom_tool", "structured"),
            ])
        )
        let s = result.summary
        #expect(s.toolsChecked == 5)
        #expect(s.matchCount == 2)
        #expect(s.overDeclaredCount == 1)
        #expect(s.underDeclaredCount == 1)
        #expect(s.indeterminateCount == 1)
    }

    // L10 — JSON canonical-shape: byte parity with Python sibling shape.
    @Test("L10 — canonicalJSON renders the documented schema with sorted keys")
    func l10_canonicalJSONShape() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let plain: PlainHandler = PlainHandler()
            func handleCall(name: String) async -> Int {
                switch name { case "t_plain": return await plain.handle(); default: return 0 }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/PlainHandler.swift", """
        struct PlainHandler {
            func handle() async -> Int { return 0 }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l10", [("t_plain", "minimal")])
        )
        let payload = try result.canonicalJSON()
        // Round-trip via JSONSerialization to assert shape.
        let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
        #expect(Set(parsed.keys) == Set(["blade", "tested_at", "harness_version", "lint_rule", "tools", "summary"]))
        #expect(parsed["lint_rule"] as? String == lintRuleID)
        #expect(parsed["blade"] as? String == "blade-l10")
        let tools = parsed["tools"] as! [String: Any]
        let inner = tools["t_plain"] as! [String: Any]
        #expect(Set(inner.keys) == Set(["audit_surface"]))
        let audit = inner["audit_surface"] as! [String: Any]
        #expect(Set(audit.keys) == Set(["declared", "actual", "result", "detail"]))
        let summary = parsed["summary"] as! [String: Any]
        #expect(Set(summary.keys) == Set([
            "tools_checked", "match_count",
            "over_declared_count", "under_declared_count", "indeterminate_count",
        ]))
        // Sorted-keys: assert the top-level keys appear in alphabetical
        // order in the serialised payload (the load-bearing byte-parity
        // guard).
        let topKeyOrder = ["blade", "harness_version", "lint_rule", "summary", "tested_at", "tools"]
        var lastIndex = -1
        for key in topKeyOrder {
            // After canonicalJSON post-processing, separator is `": "` —
            // matches Python json.dumps(indent=2) byte-shape.
            let idx = payload.range(of: "\"\(key)\":")?.lowerBound
            let pos = idx.map { payload.distance(from: payload.startIndex, to: $0) } ?? -1
            #expect(pos > lastIndex, "Key \(key) out of sorted order in canonicalJSON output")
            lastIndex = pos
        }
        // Confirm Python-style separator is in effect (no `" : ` artefact).
        #expect(!payload.contains("\" : "), "canonicalJSON output still has Foundation space-colon-space separator")
    }

    // L11 — unrecognised audit_surface value → indeterminate verdict
    @Test("L11 — unrecognised audit_surface value falls through to indeterminate")
    func l11_unknownAuditSurface() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let h: H = H()
            func handleCall(name: String) async -> Int {
                switch name { case "t": return await h.handle(); default: return 0 }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/H.swift", """
        struct H { func handle() async -> Int { return 0 } }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-l11", [("t", "totally-bogus")])
        )
        let verdict = try #require(result.tools["t"])
        #expect(verdict.auditSurface.result == "indeterminate")
        #expect(verdict.auditSurface.detail.contains("unrecognised audit_surface"))
    }

    // Extra coverage — FastMCP-style decorator registration
    @Test("FastMCP decorator with explicit name kwarg → registration found")
    func fastMCPExplicitName() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/Server.swift", """
        func makeResultWithMeta(payload: Int, meta: Int) -> Int {
            _ = appendMeta("body", "_meta: {}")
            return payload
        }
        struct Server {
            @mcp.tool(name: "syncthing_thing")
            func anyFunctionName() async -> Int {
                return makeResultWithMeta(payload: 0, meta: 0)
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-fastmcp", [("syncthing_thing", "structured")])
        )
        let verdict = try #require(result.tools["syncthing_thing"])
        #expect(verdict.auditSurface.result == "match")
    }

    // Extra coverage — addTool registration with trailing closure
    @Test("server.addTool(name:) { args in ... } trailing-closure dispatch")
    func addToolTrailingClosure() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/Server.swift", """
        struct App {
            let server: Server = Server()
            func setup() {
                server.addTool(name: "explicit_add") { args in
                    let line = "_meta: {}"
                    _ = appendMeta("body", line)
                    return 0
                }
            }
        }
        struct Server {
            func addTool(name: String, handler: @escaping (Int) -> Int) {}
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-addtool", [("explicit_add", "structured")])
        )
        let verdict = try #require(result.tools["explicit_add"])
        #expect(verdict.auditSurface.result == "match", Comment(rawValue: verdict.auditSurface.detail))
    }

    // Defensive: unparseable source file does not crash the resolver
    // (Swift parser is permissive — broken Swift parses to a tree with
    // errors but the visitor walks it fine; this is mostly a guard
    // against future SwiftSyntax tightening).
    @Test("Garbage source files are skipped, lint completes")
    func garbageFileSkipped() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/Garbage.swift", """
        this is not really valid swift @@@ }}} {{{
        """)
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let ok: OkHandler = OkHandler()
            func handleCall(name: String) async -> Int {
                switch name { case "t_ok": return await ok.handle(); default: return 0 }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/OkHandler.swift", """
        func makeResultWithMeta(payload: Int, meta: Int) -> Int {
            _ = appendMeta("body", "_meta: {}")
            return payload
        }
        struct OkHandler {
            func handle() async -> Int { return makeResultWithMeta(payload: 0, meta: 0) }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-garbage", [("t_ok", "structured")])
        )
        let verdict = try #require(result.tools["t_ok"])
        #expect(verdict.auditSurface.result == "match")
    }

    // Public constants are exported and stable
    @Test("Public constants exported — appendMeta is the SOLE canonical emit (AUD-04-13)")
    func publicConstants() {
        #expect(lintRuleID == "S-AUD-001")
        #expect(canonicalEmitNames == ["appendMeta"])
        // makeResultWithMeta bare-name trust removed in v0.4.0 — it is a
        // per-blade wrapper, not a library symbol.
        #expect(!canonicalEmitNames.contains("makeResultWithMeta"))
        #expect(maxResolutionDepth == 3)
    }

    // MARK: - AUD-04-13 — wrapper body resolution + tri-state emission

    // (a) blade-local makeResultWithMeta free function whose body calls
    // appendMeta → structured match, resolved via the wrapper path (the
    // name itself is no longer trusted).
    @Test("A13a — blade-local makeResultWithMeta calling appendMeta → match via body resolution")
    func aud0413a_wrapperResolvedByBody() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let honest: HonestHandler = HonestHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_honest":
                    return await honest.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/HonestHandler.swift", """
        func makeResultWithMeta(payload: String, metaLine: String) -> String {
            return appendMeta(payload, metaLine)
        }
        struct HonestHandler {
            func handle() async -> Int {
                _ = makeResultWithMeta(payload: "body", metaLine: "_meta: {}")
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-a13a", [("blade_honest", "structured")])
        )
        let verdict = try #require(result.tools["blade_honest"])
        #expect(verdict.auditSurface.result == "match", Comment(rawValue: verdict.auditSurface.detail))
        #expect(verdict.auditSurface.actual == "structured")
    }

    // (b) THE AUD-04-13 regression case: a drifted makeResultWithMeta
    // that never calls appendMeta. Under v0.3.0's bare-name trust this
    // linted "structured" (match); it must now be over-declared.
    @Test("A13b — drifted makeResultWithMeta NOT calling appendMeta → over-declared (regression)")
    func aud0413b_driftedWrapperOverDeclared() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let drifted: DriftedHandler = DriftedHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_drifted":
                    return await drifted.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/DriftedHandler.swift", """
        func makeResultWithMeta(payload: String, metaLine: String) -> String {
            // Drifted wrapper — returns the bare payload, no envelope.
            return payload
        }
        struct DriftedHandler {
            func handle() async -> Int {
                _ = makeResultWithMeta(payload: "body", metaLine: "_meta: {}")
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-a13b", [("blade_drifted", "structured")])
        )
        let verdict = try #require(result.tools["blade_drifted"])
        #expect(verdict.auditSurface.result == "over-declared")
        #expect(verdict.auditSurface.actual == "minimal")
    }

    // (c) switch-dispatch registration whose handler type is not defined
    // anywhere in the tree → indeterminate (resolution failure is not
    // proof of non-emission), NOT over-declared.
    @Test("A13c — handler type unresolvable → indeterminate, not over-declared")
    func aud0413c_unresolvableHandlerIndeterminate() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let ghost: GhostHandler = GhostHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_ghost":
                    return await ghost.handle()
                default: return 0
                }
            }
        }
        """)
        // Note: GhostHandler is deliberately NOT defined in any fixture file.
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-a13c", [("blade_ghost", "structured")])
        )
        let verdict = try #require(result.tools["blade_ghost"])
        #expect(verdict.auditSurface.result == "indeterminate")
        #expect(verdict.auditSurface.actual == "indeterminate")
        #expect(verdict.auditSurface.detail.contains("could not be statically resolved"))
        #expect(result.summary.indeterminateCount == 1)
        #expect(result.summary.overDeclaredCount == 0)
    }

    // (d) wrapper that is a static method on a utility type calling
    // appendMeta → match via the typeMethodsIndex fallback.
    @Test("A13d — static-method wrapper on a utility type → match via typeMethodsIndex fallback")
    func aud0413d_staticMethodWrapper() throws {
        let fx = try BladeFixture()
        defer { fx.cleanup() }
        _ = try fx.write(file: "Sources/Blade/ToolRegistry.swift", """
        struct Registry {
            let typed: TypedHandler = TypedHandler()
            func handleCall(name: String) async -> Int {
                switch name {
                case "blade_typed":
                    return await typed.handle()
                default: return 0
                }
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/ResultKit.swift", """
        enum ResultKit {
            static func finishWithMeta(_ payload: String, _ metaLine: String) -> String {
                return appendMeta(payload, metaLine)
            }
        }
        """)
        _ = try fx.write(file: "Sources/Blade/Tools/TypedHandler.swift", """
        struct TypedHandler {
            func handle() async -> Int {
                _ = ResultKit.finishWithMeta("body", "_meta: {}")
                return 0
            }
        }
        """)
        let result = lintBlade(
            bladeSourceRoot: fx.root,
            catalogEntry: catalog("blade-a13d", [("blade_typed", "structured")])
        )
        let verdict = try #require(result.tools["blade_typed"])
        #expect(verdict.auditSurface.result == "match", Comment(rawValue: verdict.auditSurface.detail))
        #expect(verdict.auditSurface.actual == "structured")
    }
}
