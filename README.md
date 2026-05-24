# stallari-mcp-helpers (Swift)

Canonical helpers for Swift MCP servers targeting **Stallari**'s contract surface — a tight Swift Package that lets your tools emit the `_meta` audit envelope the Stallari assembler expects, without you rolling your own.

If you're porting a Swift MCP server to Stallari and want first-party-tier conformance, this is the on-ramp.

## About Stallari

Stallari is an agentic personal-knowledge-management platform. It runs [MCP servers](https://modelcontextprotocol.io) as its tool surface — the way it talks to email providers, calendars, smart-home hubs, source control, cloud infra, etc. Your MCP server dispatches through Stallari's assembler, which audits each tool call against a wire-shape contract before lifting the result into the LLM's context. This package provides the canonical helpers that make a Swift MCP server emit that contract cleanly.

## Sister packages

| Language | Package | Source |
|---|---|---|
| **Python** | [`stallari-mcp-helpers` on PyPI](https://pypi.org/project/stallari-mcp-helpers/) | [`stallari-mcp-helpers`](https://github.com/Groupthink-dev/stallari-mcp-helpers) |
| **TypeScript** | [`stallari-mcp-helpers` on npm](https://www.npmjs.com/package/stallari-mcp-helpers) | [`stallari-mcp-helpers-ts`](https://github.com/Groupthink-dev/stallari-mcp-helpers-ts) |
| **Swift** | `MCPHelpers` via Swift Package Manager | this repo |

All three packages stay in lockstep on the wire shape — `meta_envelope(...)` in Python, `formatMetaLine(...)` in TypeScript, and `formatMetaLine(...)` in Swift all emit byte-equivalent `_meta` envelopes for the same input.

## What this is

One small module:

- **`MCPHelpers`** — renders the canonical `_meta: {...}` JSON-tail block the Stallari assembler lifts into its `ContextPacket.provenance` audit trail. Locked encoding: tight JSON separators, alphabetically-sorted `filtered_by`, required/optional field discipline matching the DD-338 wire contract.

This package does **not** ship MCP-server scaffolding, tool registration, HTTP/IPC, inference, or domain-attribution primitives. It's deliberately small.

## Audience

Direct consumers (future, post Stallari W5 Swift wave):

- **First-party Stallari Swift MCP servers** — `apple-mail-blade-mcp`, `apple-notes-blade-mcp`, and the Swift surface of `stallari-vault` served as `stallari-blade-mcp` via the daemon. These don't yet ship the `_meta` envelope; this package lands ahead of W5 so the wave can adopt natively.

Broader audience:

- **Any Swift MCP author** who wants their server to dispatch through Stallari at first-party-tier conformance. You don't have to be on the Stallari team. Add the SPM dependency, use the helpers, declare your tool capabilities honestly in your pack manifest, and the assembler will treat your tool as a first-class participant.

If you're integrating a third-party MCP that you don't control, the Stallari adapter-transform layer (deterministic YAML, in-process) handles you separately — you don't need this library.

## Install (Swift Package Manager)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Groupthink-dev/stallari-mcp-helpers-swift", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyBlade",
        dependencies: [
            .product(name: "MCPHelpers", package: "stallari-mcp-helpers-swift"),
        ]
    ),
]
```

Requires Swift 6.0+, macOS 14+ or iOS 17+.

## Quick start — emitting a `_meta` envelope

```swift
import MCPHelpers

func mySearchTool(query: String, scope: String = "personal") async throws -> String {
    let records = try await upstreamAPI.search(query, filter: "scope=\(scope)")
    let body = formatRecords(records)

    let meta = MetaEnvelope(
        matchedTotal: records.totalMatched,
        returned: records.items.count,
        latencyMs: records.latencyMs,
        filteredBy: ["scope=\(scope)", "query=\(query)"],
        redactions: [],         // required, empty allowed
        nextCursor: nil          // required, nil allowed
    )
    return appendMeta(body, try formatMetaLine(meta))
}
```

Output (assembler-side regex contract: `\n\n_meta: (\{.*\})$`):

```
<your body>

_meta: {"matched_total":42,"returned":10,"latency_ms":234,"filtered_by":["query=foo","scope=personal"],"redactions":[],"next_cursor":null}
```

JSON keys are emitted with snake-case names (`matched_total`, `latency_ms`, `filtered_by`, `next_cursor`) for byte-parity with the Python and TypeScript sister packages — Swift idiomatic camelCase on the API surface, canonical snake-case on the wire.

## Your manifest

Per tool in your pack catalog entry:

```json
{
  "name": "my_search_tool",
  "granularity": {
    "scope_filtering": "server-side",
    "deterministic_ordering": "stable",
    "audit_surface": "structured",
    "domain_scope": "single"
  }
}
```

Four honest declarations. If you implement `scope_filtering: server-side` you must actually filter at the upstream API. If you declare `deterministic_ordering: stable` your output must be reproducible. If you declare `audit_surface: structured` your tool must emit `formatMetaLine(...)` on every call.

Stallari's conformance harness verifies these claims against your actual tool behaviour at pack-acceptance time. Honest degraded declarations always pass; lying about a capability fails. Start with the most conservative declarations and bump each axis as you implement the corresponding behaviour.

## What you don't have to think about

- Exact JSON encoding of `_meta` envelopes (separator choice, sort order)
- Field-presence rules (required vs optional)
- Whether to round `latencyMs`
- The assembler-side `ContextPacket` shape that consumes your envelopes
- Future contract evolution — the library version-pins the wire shape; the Python and TypeScript sisters stay in lockstep

## API reference

```swift
public struct MetaEnvelope: Sendable {
    public let matchedTotal: Int
    public let returned: Int
    public let latencyMs: Int
    public let filteredBy: [String]        // alphabetically sorted in output
    public let redactions: [String]        // required, defaults to []
    public let nextCursor: String?         // required, nil is valid
    public let errorNotes: [String]?       // optional, omitted when nil or empty

    public init(
        matchedTotal: Int,
        returned: Int,
        latencyMs: Int,
        filteredBy: [String],
        redactions: [String] = [],
        nextCursor: String? = nil,
        errorNotes: [String]? = nil
    )
}

public func formatMetaLine(_ meta: MetaEnvelope) throws -> String
public func appendMeta(_ payload: String, _ metaLine: String) -> String
```

## Versioning

SemVer. `0.x.y` series while the public API stabilises; `1.0.0` once consumer blade-mcps have shipped against `0.x` for >30 days with no API churn.

Breaking changes after `1.0.0` get a one-minor-version deprecation window (`v1.y` annotates `@available(deprecated)`, `v2.0` removes).

## License

MIT. See `LICENSE`.

## Contributing

This is internal Stallari plumbing during the `0.x` series — issues + PRs accepted but the API surface is still settling. Submit issues at the [GitHub tracker](https://github.com/Groupthink-dev/stallari-mcp-helpers-swift/issues).
