// S-AUD-001 — Static AST-based audit-surface honesty linter for Swift
// blade-mcps (DD-338 Phase B Swift sibling).
//
// Cross-language sister to ``stallari_mcp_helpers.lint`` (Python) and the
// TS sibling. Static analog of the runtime probe at
// ``stallari_capability_conformance.probe.LiveMCPToolProbe`` — walks the
// blade source tree with SwiftSyntax, identifies tool registration sites,
// and checks whether each tool's emission path transitively calls a
// canonical ``MCPHelpers`` envelope-emitter.
//
// Recognised tool-registration patterns (the Swift blade-mcp surface in
// May 2026):
//
//   1. Switch-dispatch ToolRegistry (apple-notes / apple-mail pattern).
//      ```swift
//      switch name {
//      case "apple_notes_list_folders":
//          return await listFolders.handle(arguments: arguments)
//      ...
//      ```
//      The string literal is the tool name; the call target's identifier
//      identifies the handler instance, which the resolver maps back to a
//      property declaration to find the handler type (e.g.
//      ``ListFoldersHandler``). The handler type's ``handle(arguments:)``
//      method body is the emission scan target.
//
//   2. FastMCP-style decorator (any module prefix — ``mcp``, ``server``,
//      ``app``, ``self.mcp``). Matches ``@<x>.tool``, ``@<x>.tool()``,
//      ``@<x>.tool(name: "X")``. Mirrors the Python sister so a future
//      Swift FastMCP analog wouldn't require lint rework.
//
//   3. Imperative ``server.addTool(name: "x", ...) { args in ... }``
//      registration with a trailing closure. The closure body is the
//      emission scan target.
//
// Canonical emit names: ``appendMeta`` ONLY (the low-level joiner in
// ``Encoder.swift``) — v0.4.0 / AUD-04-13. ``makeResultWithMeta`` was
// removed from the trusted set: it is a per-blade hand-rolled wrapper,
// not a symbol this library defines, and trusting it by bare name meant
// a drifted wrapper that never calls ``appendMeta`` still linted
// "structured" — the exact over-declaration S-AUD-001 exists to catch.
// A blade's ``makeResultWithMeta`` (or any other wrapper, free function
// or type method) now satisfies the lint only when the resolver finds
// its actual body and that body transitively calls ``appendMeta``
// (the wrapper-resolution path in ``functionIsCanonical``).
//
// Resolution depth is capped at ``maxResolutionDepth`` hops to keep the
// lint tractable and deterministic — deeper indirection becomes
// ``indeterminate`` rather than guessed. Likewise, a registration whose
// handler body cannot be statically resolved (handler property type or
// method missing from the parsed tree) is ``indeterminate`` — a
// resolution failure is not proof of non-emission.
//
// JSON output shape is byte-identical to the Python sibling's
// ``LintResult.to_dict()`` rendered via ``json.dumps(..., sort_keys=True,
// indent=2)``. We rely on Foundation's ``JSONSerialization`` with
// ``.sortedKeys`` + ``.prettyPrinted`` to match the alphabetical key
// ordering — see ``LintResult.canonicalJSON()`` for the contract.
//
// IMPORTANT — JSON key ordering note (per
// ``[[feedback_swift_jsonencoder_key_order]]``): the CLI output and any
// sidecar file MUST be emitted via ``canonicalJSON()``. The
// ``Codable``-conforming structs below are convenient for in-process
// consumption but Foundation's ``JSONEncoder`` does not preserve
// CodingKey insertion order across all minor Swift versions; relying on
// it would produce non-deterministic sidecar bytes.
//
// Author: DD-338 Phase B Swift coding subagent (2026-05-24).

import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Public constants

/// Lint rule identifier surfaced in the sidecar JSON.
public let lintRuleID = "S-AUD-001"

/// Canonical emit names whose call inside a tool-handler body counts as
/// "structured" emission — ``appendMeta`` only.
///
/// ``makeResultWithMeta`` was REMOVED in v0.4.0 (AUD-04-13): it is a
/// per-blade hand-rolled wrapper, not a library symbol, and bare-name
/// trust let a drifted wrapper that never calls ``appendMeta`` lint
/// "structured". A blade's ``makeResultWithMeta`` (or any wrapper) now
/// satisfies the lint only when the resolver finds its actual body and
/// that body transitively calls ``appendMeta`` — the existing
/// wrapper-resolution path (``functionIsCanonical``, including the
/// cross-module ``typeMethodsIndex`` fallback for static/instance-method
/// wrappers) provides this.
public let canonicalEmitNames: Set<String> = ["appendMeta"]

/// Maximum number of wrapper-function hops the resolver will follow when
/// deciding whether an in-blade identifier transitively reaches a
/// canonical emit name. Three hops handles the common patterns:
///   1. direct call: handler body → ``appendMeta``
///   2. wrapper-in-blade: handler body → blade-local
///      ``makeResultWithMeta`` (resolved by body, not name) → ``appendMeta``
///   3. one extra hop: handler body → custom wrapper → blade-local
///      ``makeResultWithMeta`` → ``appendMeta``
public let maxResolutionDepth = 3

// MARK: - Result types

/// Per-tool verdict carrier — inner ``audit_surface`` block whose JSON
/// shape mirrors the live probe's sidecar.
public struct AuditSurfaceVerdict: Sendable, Equatable, Codable {
    public let declared: String   // "structured" | "minimal" | "none"
    public let actual: String     // "structured" | "minimal" | "indeterminate"
    public let result: String     // "match" | "over-declared" | "under-declared" | "indeterminate"
    public let detail: String

    public init(declared: String, actual: String, result: String, detail: String) {
        self.declared = declared
        self.actual = actual
        self.result = result
        self.detail = detail
    }
}

public struct ToolVerdict: Sendable, Equatable, Codable {
    public let auditSurface: AuditSurfaceVerdict

    public init(auditSurface: AuditSurfaceVerdict) {
        self.auditSurface = auditSurface
    }

    enum CodingKeys: String, CodingKey {
        case auditSurface = "audit_surface"
    }
}

public struct LintSummary: Sendable, Equatable, Codable {
    public let toolsChecked: Int
    public let matchCount: Int
    public let overDeclaredCount: Int
    public let underDeclaredCount: Int
    public let indeterminateCount: Int

    public init(
        toolsChecked: Int,
        matchCount: Int,
        overDeclaredCount: Int,
        underDeclaredCount: Int,
        indeterminateCount: Int
    ) {
        self.toolsChecked = toolsChecked
        self.matchCount = matchCount
        self.overDeclaredCount = overDeclaredCount
        self.underDeclaredCount = underDeclaredCount
        self.indeterminateCount = indeterminateCount
    }

    enum CodingKeys: String, CodingKey {
        case toolsChecked = "tools_checked"
        case matchCount = "match_count"
        case overDeclaredCount = "over_declared_count"
        case underDeclaredCount = "under_declared_count"
        case indeterminateCount = "indeterminate_count"
    }
}

/// Top-level verdict aggregate produced by ``lintBlade``.
public struct LintResult: Sendable, Equatable, Codable {
    public let blade: String
    public let testedAt: String      // ISO-8601 seconds-precision UTC
    public let harnessVersion: String
    public let lintRule: String      // always ``lintRuleID``
    public let tools: [String: ToolVerdict]
    public let summary: LintSummary

    public init(
        blade: String,
        testedAt: String,
        harnessVersion: String,
        lintRule: String = lintRuleID,
        tools: [String: ToolVerdict],
        summary: LintSummary
    ) {
        self.blade = blade
        self.testedAt = testedAt
        self.harnessVersion = harnessVersion
        self.lintRule = lintRule
        self.tools = tools
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case blade
        case testedAt = "tested_at"
        case harnessVersion = "harness_version"
        case lintRule = "lint_rule"
        case tools
        case summary
    }

    /// Render the verdict as a JSON string with byte-parity to the Python
    /// sibling's ``json.dumps(result.to_dict(), indent=2, sort_keys=True)``.
    ///
    /// Implementation: build a `[String: Any]` dictionary tree with the
    /// canonical keys (snake_case) and run it through ``JSONSerialization``
    /// with ``.sortedKeys`` + ``.prettyPrinted``. We deliberately do NOT
    /// use ``JSONEncoder.encode(self)`` because Foundation's keyed encoder
    /// order is implementation-defined; see header comment.
    public func canonicalJSON() throws -> String {
        var toolsDict: [String: Any] = [:]
        for (name, verdict) in tools {
            toolsDict[name] = [
                "audit_surface": [
                    "declared": verdict.auditSurface.declared,
                    "actual": verdict.auditSurface.actual,
                    "result": verdict.auditSurface.result,
                    "detail": verdict.auditSurface.detail,
                ]
            ]
        }
        let summaryDict: [String: Any] = [
            "tools_checked": summary.toolsChecked,
            "match_count": summary.matchCount,
            "over_declared_count": summary.overDeclaredCount,
            "under_declared_count": summary.underDeclaredCount,
            "indeterminate_count": summary.indeterminateCount,
        ]
        let root: [String: Any] = [
            "blade": blade,
            "tested_at": testedAt,
            "harness_version": harnessVersion,
            "lint_rule": lintRule,
            "tools": toolsDict,
            "summary": summaryDict,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let s = String(data: data, encoding: .utf8) else {
            throw LintError.encodingFailed
        }
        // Foundation pretty-printed JSON differs from Python
        // `json.dumps(indent=2, sort_keys=True)` in two cosmetic ways
        // we MUST normalise for cross-language byte-parity:
        //
        //   1. Key/value separator: Foundation emits `"key" : value`
        //      (space-colon-space); Python emits `"key": value`
        //      (colon-space). The pattern `" : ` only occurs at a
        //      key/value boundary in valid JSON — embedded quotes in
        //      string values are escaped to `\"`, so a literal
        //      `" : ` cannot appear mid-value.
        //
        //   2. Forward-slash escaping: Foundation emits `\/` whereas
        //      Python emits a bare `/`. Both are valid JSON; we strip
        //      the escapes for byte-parity. `\/` cannot appear inside
        //      a string value other than as the literal sequence
        //      "backslash + forward-slash", which is invalid in JSON
        //      strings (the only valid backslash escapes are
        //      `\" \\ \/ \b \f \n \r \t \uXXXX`); Python's json module
        //      decodes both forms to the same character so round-trip
        //      remains lossless.
        return s
            .replacingOccurrences(of: "\" : ", with: "\": ")
            .replacingOccurrences(of: "\\/", with: "/")
    }
}

public enum LintError: Error, Equatable {
    case encodingFailed
    case catalogNotReadable(String)
}

// MARK: - Public entrypoint

/// Statically lint a Swift blade-mcp source root for DD-338 audit-surface
/// honesty (S-AUD-001).
///
/// - Parameters:
///   - bladeSourceRoot: filesystem path to the blade's Swift source root.
///     May be the repo root (e.g. ``~/src/apple-notes-blade-mcp/``) or
///     the inner sources directory (e.g.
///     ``~/src/apple-notes-blade-mcp/Sources/AppleNotesBlade/``). The
///     walker rglobs ``*.swift`` files either way.
///   - catalogEntry: parsed catalog-JSON dictionary — must include
///     ``name`` and a ``tools`` array of per-tool declarations whose
///     ``granularity.audit_surface`` is one of
///     ``structured`` / ``minimal`` / ``none``.
public func lintBlade(
    bladeSourceRoot: URL,
    catalogEntry: [String: Any]
) -> LintResult {
    let resolver = SourceResolver.build(root: bladeSourceRoot)
    let registry = resolver.collectToolRegistrations()

    var toolsBlock: [String: ToolVerdict] = [:]
    var counts = (match: 0, over: 0, under: 0, indeterminate: 0)

    let bladeName = (catalogEntry["name"] as? String) ?? bladeSourceRoot.lastPathComponent
    let catalogTools = (catalogEntry["tools"] as? [[String: Any]]) ?? []

    for toolEntry in catalogTools {
        guard let toolName = toolEntry["name"] as? String else { continue }
        let granularity = toolEntry["granularity"] as? [String: Any] ?? [:]
        let declared = (granularity["audit_surface"] as? String) ?? "minimal"

        let verdict: AuditSurfaceVerdict
        if declared == "none" {
            verdict = AuditSurfaceVerdict(
                declared: "none",
                actual: "indeterminate",
                result: "match",
                detail: (
                    "audit_surface=none — tool returns byte payloads where the "
                    + "_meta envelope is N/A; emission status is not inspected."
                )
            )
        } else if let registration = registry[toolName] {
            if let emits = resolver.bodyEmits(registration: registration) {
                verdict = verdictForDeclared(declared, emits: emits)
            } else {
                // Resolution failure, NOT proof of non-emission
                // (AUD-04-13): do not report over-declared when the
                // lint simply could not see the body.
                verdict = AuditSurfaceVerdict(
                    declared: declared,
                    actual: "indeterminate",
                    result: "indeterminate",
                    detail: (
                        "tool registration matched but the handler body "
                        + "could not be statically resolved (handler "
                        + "property type or method not found in the parsed "
                        + "tree) — emission status unknown."
                    )
                )
            }
        } else {
            verdict = AuditSurfaceVerdict(
                declared: declared,
                actual: "indeterminate",
                result: "indeterminate",
                detail: (
                    "no Swift registration matched tool name \(toolName); "
                    + "expected one of: switch-dispatch case \"\(toolName)\", "
                    + "@x.tool(name: \"\(toolName)\") decorator, or "
                    + "server.addTool(name: \"\(toolName)\", ...) call."
                )
            )
        }

        toolsBlock[toolName] = ToolVerdict(auditSurface: verdict)
        switch verdict.result {
        case "match": counts.match += 1
        case "over-declared": counts.over += 1
        case "under-declared": counts.under += 1
        default: counts.indeterminate += 1
        }
    }

    let summary = LintSummary(
        toolsChecked: toolsBlock.count,
        matchCount: counts.match,
        overDeclaredCount: counts.over,
        underDeclaredCount: counts.under,
        indeterminateCount: counts.indeterminate
    )

    return LintResult(
        blade: bladeName,
        testedAt: isoUTCNow(),
        harnessVersion: MCPHelpers.version,
        tools: toolsBlock,
        summary: summary
    )
}

// MARK: - Verdict construction

/// Construct a verdict from a CONCRETE emission decision. Callers must
/// only invoke this with a genuinely-inspected `Bool` — an unresolvable
/// handler body (`bodyEmits` → nil) is handled upstream as
/// `indeterminate` and never reaches here (AUD-04-13).
private func verdictForDeclared(_ declared: String, emits: Bool) -> AuditSurfaceVerdict {
    let actual = emits ? "structured" : "minimal"
    if declared == "structured" {
        if emits {
            return AuditSurfaceVerdict(
                declared: "structured",
                actual: "structured",
                result: "match",
                detail: (
                    "tool handler body calls the canonical emit (appendMeta), "
                    + "directly or via a wrapper whose resolved body "
                    + "transitively reaches it."
                )
            )
        }
        return AuditSurfaceVerdict(
            declared: "structured",
            actual: "minimal",
            result: "over-declared",
            detail: (
                "catalog declares audit_surface=structured but tool handler "
                + "body does not call any canonical emit within the resolved "
                + "graph (depth ≤\(maxResolutionDepth))."
            )
        )
    }
    if declared == "minimal" {
        if emits {
            return AuditSurfaceVerdict(
                declared: "minimal",
                actual: "structured",
                result: "under-declared",
                detail: (
                    "catalog declares audit_surface=minimal but tool handler "
                    + "body calls a canonical emit — declare structured instead."
                )
            )
        }
        return AuditSurfaceVerdict(
            declared: "minimal",
            actual: "minimal",
            result: "match",
            detail: "catalog declares minimal and handler does not call any canonical emit."
        )
    }
    return AuditSurfaceVerdict(
        declared: declared,
        actual: actual,
        result: "indeterminate",
        detail: (
            "unrecognised audit_surface value \(declared) in catalog; "
            + "expected one of structured / minimal / none."
        )
    )
}

// MARK: - ISO-8601 helper

private func isoUTCNow() -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: Date())
}

// MARK: - Registration carrier

/// One detected tool registration with enough context for the resolver to
/// scan its emission graph. Either a direct closure body (``inlineBody``)
/// OR a handler-call dispatch (``handlerCall``) that we resolve to a
/// type's method body.
struct ToolRegistration {
    enum Kind {
        /// Emission target is the closure body provided at registration
        /// time (FastMCP decorator method body, or
        /// ``server.addTool { ... }`` trailing closure).
        case inlineBody(body: CodeBlockSyntax, moduleKey: ModuleKey)
        /// Emission target is a single ``await <handlerExpr>.<method>(...)``
        /// call — the resolver maps the handler identifier to a
        /// declared property type and walks its method body.
        case handlerCall(handlerName: String, methodName: String, moduleKey: ModuleKey)
    }
    let toolName: String
    let kind: Kind
}

/// Stable identifier for a parsed source file — used to scope name
/// resolution to a single module (import set, in-file declarations) when
/// determining wrapper canonicality.
struct ModuleKey: Hashable {
    let url: URL
}

// MARK: - Source resolver

/// Parses every ``*.swift`` file under the blade root and offers
/// query primitives the verdict layer needs.
final class SourceResolver {

    /// Per-file parsed view.
    struct ModuleInfo {
        let url: URL
        let tree: SourceFileSyntax
        /// All function/method declarations indexed by name (last-write
        /// wins on collision — fine for the granularity we need).
        var freeFunctions: [String: FunctionDeclSyntax] = [:]
        /// Type declarations (struct/class/actor/enum) keyed by name.
        /// Stores the inner method map: ``methods[typeName][methodName]``.
        var methods: [String: [String: FunctionDeclSyntax]] = [:]
        /// Property → declared type name (for handler-instance dispatch).
        /// e.g. ``listFolders → ListFoldersHandler`` from
        /// ``private let listFolders: ListFoldersHandler``.
        var propertyTypes: [String: String] = [:]
        /// Top-level switch-dispatch registrations.
        var switchRegistrations: [(toolName: String, handlerName: String, methodName: String)] = []
        /// FastMCP-decorator registrations (closure body lookup by tool name).
        var decoratorRegistrations: [(toolName: String, body: CodeBlockSyntax)] = []
        /// ``server.addTool(name:...) { ... }`` registrations.
        var addToolRegistrations: [(toolName: String, body: CodeBlockSyntax)] = []
    }

    let root: URL
    var modules: [ModuleKey: ModuleInfo] = [:]
    /// Index of type-name → (module-key, method-name → declaration). A
    /// type definition can live in any source file; we union across the
    /// whole tree.
    var typeMethodsIndex: [String: [String: FunctionDeclSyntax]] = [:]
    /// Cache of resolved canonicality on free-function symbols, keyed by
    /// (moduleKey, name). Memoises the recursion in ``functionIsCanonical``.
    var canonicalCache: [String: Bool] = [:]

    private init(root: URL) {
        self.root = root
    }

    /// Walk ``root`` recursively, parse every Swift file, and pre-index
    /// the things the verdict layer needs.
    static func build(root: URL) -> SourceResolver {
        let resolver = SourceResolver(root: root)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return resolver
        }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            // Skip build artefacts that may have leaked under root.
            if url.path.contains("/.build/") || url.path.contains("/DerivedData/") {
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let source = String(data: data, encoding: .utf8) else {
                continue
            }
            let tree = Parser.parse(source: source)
            let key = ModuleKey(url: url)
            var info = ModuleInfo(url: url, tree: tree)
            ModuleFactCollector.collect(into: &info, tree: tree)
            resolver.modules[key] = info
            // Union type-method index.
            for (typeName, methods) in info.methods {
                var merged = resolver.typeMethodsIndex[typeName] ?? [:]
                for (m, fn) in methods { merged[m] = fn }
                resolver.typeMethodsIndex[typeName] = merged
            }
        }
        return resolver
    }

    /// Build the registration index keyed by tool name. Switch-dispatch,
    /// decorator, and ``addTool`` registrations all flow through here;
    /// last writer wins on duplicate tool names (the catalog has the
    /// authoritative list anyway).
    func collectToolRegistrations() -> [String: ToolRegistration] {
        var out: [String: ToolRegistration] = [:]
        for (key, info) in modules {
            for (toolName, handlerName, methodName) in info.switchRegistrations {
                out[toolName] = ToolRegistration(
                    toolName: toolName,
                    kind: .handlerCall(
                        handlerName: handlerName,
                        methodName: methodName,
                        moduleKey: key
                    )
                )
            }
            for (toolName, body) in info.decoratorRegistrations {
                out[toolName] = ToolRegistration(
                    toolName: toolName,
                    kind: .inlineBody(body: body, moduleKey: key)
                )
            }
            for (toolName, body) in info.addToolRegistrations {
                out[toolName] = ToolRegistration(
                    toolName: toolName,
                    kind: .inlineBody(body: body, moduleKey: key)
                )
            }
        }
        return out
    }

    /// Top-level emission decision: does this registration's target body
    /// transitively reach a canonical emit name?
    ///
    /// Tri-state (AUD-04-13):
    ///   - `true` / `false` — a genuinely-inspected body does / does not
    ///     reach a canonical emit.
    ///   - `nil` — resolution failure: for `.handlerCall`, the handler
    ///     property's type could not be resolved, the type's method was
    ///     not found in the parsed tree, or the method has no body. These
    ///     are NOT proof of non-emission; the caller must surface them as
    ///     `indeterminate`, never `over-declared`.
    func bodyEmits(registration: ToolRegistration) -> Bool? {
        switch registration.kind {
        case .inlineBody(let body, let key):
            return blockCallsCanonical(body: body, moduleKey: key, depth: 0)
        case .handlerCall(let handlerName, let methodName, let key):
            // Resolve handler property → declared type.
            guard let module = modules[key],
                  let typeName = resolveHandlerType(name: handlerName, in: module) else {
                return nil
            }
            guard let methods = typeMethodsIndex[typeName],
                  let method = methods[methodName] else {
                return nil
            }
            guard let body = method.body else { return nil }
            return blockCallsCanonical(body: body, moduleKey: key, depth: 0)
        }
    }

    /// Walk a code block for any call whose target name is canonical (or
    /// a wrapper that resolves to canonical inside the recursion limit).
    private func blockCallsCanonical(
        body: CodeBlockSyntax,
        moduleKey: ModuleKey,
        depth: Int
    ) -> Bool {
        if depth > maxResolutionDepth { return false }
        let visitor = CallSiteCollector(viewMode: .all)
        visitor.walk(body)
        for callName in visitor.callNames {
            if canonicalEmitNames.contains(callName) {
                return true
            }
            // Wrapper-function resolution: is there a free function in
            // the same module whose body itself reaches canonical?
            if functionIsCanonical(name: callName, moduleKey: moduleKey, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    /// Resolve a property identifier to its declared type within a module.
    /// e.g. ``listFolders`` → ``ListFoldersHandler``.
    private func resolveHandlerType(name: String, in module: ModuleInfo) -> String? {
        return module.propertyTypes[name]
    }

    /// Memoised: is the named function in this module a canonical
    /// wrapper? A wrapper is canonical if its body calls a canonical
    /// emit (recursively, up to the depth cap).
    ///
    /// Resolution order: same-module free function → cross-module free
    /// function → cross-module ``typeMethodsIndex`` (a wrapper may be a
    /// static or instance method on a utility type, e.g.
    /// ``ResultKit.makeResultWithMeta`` — AUD-04-13 extension; without
    /// this fallback, method-shaped wrappers would silently lint as
    /// non-canonical).
    private func functionIsCanonical(
        name: String,
        moduleKey: ModuleKey,
        depth: Int
    ) -> Bool {
        if depth > maxResolutionDepth { return false }
        let cacheKey = "\(moduleKey.url.path)::\(name)::\(depth)"
        if let cached = canonicalCache[cacheKey] { return cached }
        // Search same module first; fall back to cross-module union.
        var fn: FunctionDeclSyntax? = nil
        if let module = modules[moduleKey] {
            fn = module.freeFunctions[name]
        }
        if fn == nil {
            for (_, info) in modules {
                if let candidate = info.freeFunctions[name] {
                    fn = candidate
                    break
                }
            }
        }
        if fn == nil {
            // Cross-module type-method fallback: any type's method with
            // this name. Deterministic-enough for the lint's granularity —
            // the catalog is the authority on which tools exist; here we
            // only need to know whether SOME in-tree body by this name
            // reaches the canonical emit.
            for (_, methods) in typeMethodsIndex {
                if let candidate = methods[name] {
                    fn = candidate
                    break
                }
            }
        }
        guard let function = fn, let body = function.body else {
            canonicalCache[cacheKey] = false
            return false
        }
        let result = blockCallsCanonical(body: body, moduleKey: moduleKey, depth: depth)
        canonicalCache[cacheKey] = result
        return result
    }
}

// MARK: - SwiftSyntax visitors

/// Walks a tree and populates a ``ModuleInfo`` with fact tables (free
/// functions, type → method maps, property types, switch/decorator/addTool
/// registrations).
enum ModuleFactCollector {
    static func collect(into info: inout SourceResolver.ModuleInfo, tree: SourceFileSyntax) {
        let walker = ModuleWalker(viewMode: .all)
        walker.info = info
        walker.walk(tree)
        info = walker.info
    }
}

private final class ModuleWalker: SyntaxVisitor {
    var info: SourceResolver.ModuleInfo = .init(url: URL(fileURLWithPath: "/dev/null"), tree: SourceFileSyntax(statements: CodeBlockItemListSyntax([])))

    // Track current containing type for method attribution. Stack-based
    // so nested types behave correctly.
    private var typeStack: [String] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        defer { _ = typeStack }  // silence unused warning; pop happens in visitPost
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        if typeStack.last == node.name.text { typeStack.removeLast() }
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        if typeStack.last == node.name.text { typeStack.removeLast() }
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        if typeStack.last == node.name.text { typeStack.removeLast() }
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        if typeStack.last == node.name.text { typeStack.removeLast() }
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedType = node.extendedType.trimmedDescription
        typeStack.append(extendedType)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        if let top = typeStack.last, top == node.extendedType.trimmedDescription {
            typeStack.removeLast()
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let fnName = node.name.text
        // FastMCP-style decorator? (any attribute whose name ends in
        // ``.tool``, with optional ``name:`` kwarg).
        if let toolName = fastMCPToolName(decorators: node.attributes, defaultName: fnName) {
            if let body = node.body {
                info.decoratorRegistrations.append((toolName, body))
            }
        }
        // Free function vs method attribution.
        if let owningType = typeStack.last {
            var map = info.methods[owningType] ?? [:]
            map[fnName] = node
            info.methods[owningType] = map
        } else {
            info.freeFunctions[fnName] = node
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Capture property type declarations within the active type
        // (or top-level let/var with type annotation).
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let propertyName = pattern.identifier.text
            if let typeAnnotation = binding.typeAnnotation {
                let typeText = typeAnnotation.type.trimmedDescription
                // Strip trailing optional markers; keep base type name for
                // handler lookup (handlers are typically non-optional).
                let normalised = stripTypeDecorations(typeText)
                info.propertyTypes[propertyName] = normalised
            } else if let initialiser = binding.initializer?.value {
                // Best-effort: ``private let foo = SomeType(...)`` → record
                // ``SomeType`` from the initialiser call's identifier.
                if let typeName = constructedTypeName(initialiser) {
                    info.propertyTypes[propertyName] = typeName
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        // Walk each case looking for the recognised shape:
        //   case "tool_name":
        //       return await <handler>.<method>(...)
        for caseElement in node.cases {
            guard let switchCase = caseElement.as(SwitchCaseSyntax.self) else { continue }
            guard let labelToolName = stringLiteralFromCaseLabel(switchCase.label) else { continue }
            if let (handlerName, methodName) = handlerCallInCaseBody(switchCase.statements) {
                info.switchRegistrations.append((labelToolName, handlerName, methodName))
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Detect ``something.addTool(name: "x", ...) { args in ... }``.
        guard let callee = node.calledExpression.as(MemberAccessExprSyntax.self),
              callee.declName.baseName.text == "addTool" else {
            return .visitChildren
        }
        // Extract ``name:`` argument.
        var toolName: String? = nil
        for arg in node.arguments {
            if arg.label?.text == "name", let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                toolName = singleSegmentStringLiteral(lit)
                break
            }
        }
        // Body: prefer trailing closure; fall back to a ``handler:`` /
        // last unlabelled closure argument if present.
        var body: CodeBlockSyntax? = nil
        if let trailing = node.trailingClosure {
            body = synthesiseCodeBlock(fromClosure: trailing)
        } else {
            for arg in node.arguments.reversed() {
                if let closure = arg.expression.as(ClosureExprSyntax.self) {
                    body = synthesiseCodeBlock(fromClosure: closure)
                    break
                }
            }
        }
        if let toolName, let body {
            info.addToolRegistrations.append((toolName, body))
        }
        return .visitChildren
    }
}

// MARK: - Helpers (SwiftSyntax-shape extractors)

/// Look for a FastMCP-style ``.tool`` attribute on a function decl. Returns
/// the registered tool name (either the explicit ``name:`` kwarg or the
/// function's own name) when matched; ``nil`` otherwise.
private func fastMCPToolName(
    decorators: AttributeListSyntax,
    defaultName: String
) -> String? {
    for element in decorators {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        // ``@x.tool`` and ``@x.tool()`` — attribute name is a
        // MemberTypeSyntax with trailing ``tool`` member; or just an
        // identifier ``tool`` when used unqualified.
        let name = attribute.attributeName.trimmedDescription
        // Recognised forms: anything ending in ``.tool`` or exactly ``tool``.
        let isToolDecorator = name == "tool" || name.hasSuffix(".tool")
        if !isToolDecorator { continue }
        // ``@x.tool(name: "X")`` form — pull explicit name from arguments.
        if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in arguments {
                if arg.label?.text == "name",
                   let lit = arg.expression.as(StringLiteralExprSyntax.self),
                   let s = singleSegmentStringLiteral(lit) {
                    return s
                }
            }
        }
        return defaultName
    }
    return nil
}

/// Extract a single-segment Swift string literal's text value, or nil if
/// the literal has interpolations or is otherwise non-static.
private func singleSegmentStringLiteral(_ literal: StringLiteralExprSyntax) -> String? {
    guard literal.segments.count == 1 else { return nil }
    guard let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
        return nil
    }
    return segment.content.text
}

/// Pull a string literal out of a switch-case label like ``case "x":``.
/// Returns nil if the label is a non-string-literal pattern (we only
/// recognise the simple tool-name dispatch shape).
private func stringLiteralFromCaseLabel(_ label: SwitchCaseSyntax.Label) -> String? {
    guard let switchLabel = label.as(SwitchCaseLabelSyntax.self) else { return nil }
    // We accept a single item case `case "x":` for now.
    guard switchLabel.caseItems.count == 1 else { return nil }
    guard let item = switchLabel.caseItems.first else { return nil }
    // Pattern → ExpressionPatternSyntax → StringLiteralExprSyntax.
    if let exprPattern = item.pattern.as(ExpressionPatternSyntax.self) {
        if let lit = exprPattern.expression.as(StringLiteralExprSyntax.self) {
            return singleSegmentStringLiteral(lit)
        }
    }
    return nil
}

/// Find the first ``return await <handler>.<method>(...)`` shape in a
/// case body. Returns ``(handlerName, methodName)`` or nil.
private func handlerCallInCaseBody(
    _ statements: CodeBlockItemListSyntax
) -> (String, String)? {
    for stmt in statements {
        // Recursively look at any FunctionCallExprSyntax under this
        // statement — handles ``return await x.y(...)``,
        // ``return x.y(...)``, plain ``await x.y(...)``, etc.
        let collector = FirstHandlerCallExtractor(viewMode: .all)
        collector.walk(stmt)
        if let pair = collector.match { return pair }
    }
    return nil
}

/// Walks a node and records the FIRST member-access function call shape
/// ``<handlerIdent>.<methodName>(...)`` it finds. Used to extract the
/// `(handler, method)` pair from a switch-case body.
private final class FirstHandlerCallExtractor: SyntaxVisitor {
    var match: (String, String)? = nil

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if match != nil { return .skipChildren }
        // ``await x.y(...)`` parses as ``FunctionCallExpr(calledExpr:
        // MemberAccessExpr(base: AwaitExpr | DeclRefExpr, declName: ...))``.
        // Unwrap one layer of await on the base.
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = member.declName.baseName.text
            var baseExpr = member.base
            // Strip leading `await` from base if present.
            if let await_ = baseExpr?.as(AwaitExprSyntax.self) {
                baseExpr = await_.expression
            }
            if let ref = baseExpr?.as(DeclReferenceExprSyntax.self) {
                let handlerName = ref.baseName.text
                match = (handlerName, methodName)
                return .skipChildren
            }
        }
        return .visitChildren
    }
}

/// Recursively walk a syntax node and collect the simple identifier name
/// of every call we see. Member-access calls contribute the member name
/// (e.g. ``x.foo()`` → ``foo``); bare-identifier calls contribute the
/// identifier (e.g. ``foo()`` → ``foo``).
private final class CallSiteCollector: SyntaxVisitor {
    var callNames: [String] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            callNames.append(member.declName.baseName.text)
        } else if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            callNames.append(ref.baseName.text)
        }
        return .visitChildren
    }
}

/// Wrap a closure expression's statements in a code block so the call-site
/// collector can walk it uniformly with method bodies.
private func synthesiseCodeBlock(fromClosure closure: ClosureExprSyntax) -> CodeBlockSyntax {
    return CodeBlockSyntax(statements: closure.statements)
}

/// Strip optional / array / generic angle brackets off a type's trimmed
/// description, returning a bare identifier suitable for the type-method
/// index lookup. Best-effort — exotic types (function types, tuple types)
/// return their original text and simply won't match the index.
private func stripTypeDecorations(_ type: String) -> String {
    var t = type.trimmingCharacters(in: .whitespaces)
    while t.hasSuffix("?") || t.hasSuffix("!") {
        t.removeLast()
    }
    // For generic types like ``Foo<Bar>``, keep the outer name for
    // resolution (rare in handler-instance dispatch but defensive).
    if let lt = t.firstIndex(of: "<") {
        t = String(t[..<lt])
    }
    return t
}

/// If an initialiser is a simple ``TypeName(...)`` call, return the type
/// identifier. Returns nil for nested member-access constructors and
/// closure-builder shapes.
private func constructedTypeName(_ expr: ExprSyntax) -> String? {
    if let call = expr.as(FunctionCallExprSyntax.self) {
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let typeExpr = call.calledExpression.as(TypeExprSyntax.self) {
            return typeExpr.type.trimmedDescription
        }
    }
    return nil
}
