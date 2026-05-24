# Changelog

All notable changes to `MCPHelpers` (Swift) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-24

Initial release. Sister package to [stallari-mcp-helpers (Python)](https://pypi.org/project/stallari-mcp-helpers/) and [stallari-mcp-helpers (TypeScript)](https://www.npmjs.com/package/stallari-mcp-helpers) — same wire contract, same `_meta` envelope shape, idiomatic Swift API.

### Added
- `MCPHelpers` Swift module — canonical `_meta: {...}` JSON-tail envelope builder for Swift MCP servers targeting Stallari's contract surface.
- `MetaEnvelope` struct + `formatMetaLine(_:)` builder + `appendMeta(_:_:)` joiner. Wire-shape locked at parity with the Python + TypeScript sisters; cross-language byte-equivalent output for the same input.

#### `MetaEnvelope` struct

- `MetaEnvelope` — `Sendable + Equatable + Codable` struct with `matchedTotal: Int`, `returned: Int`, `latencyMs: Int`, `filteredBy: [String]`, `redactions: [String]`, `nextCursor: String?`, `errorNotes: [String]?` fields. Init signature is keyword-only matching the Python sister's `meta_envelope(...)` kwarg-only pattern. JSON encoding uses snake_case keys (`matched_total`, `latency_ms`, `filtered_by`, `next_cursor`, `error_notes`) via the `CodingKeys` enum.
- `MCPHelpers.version: String` — module version constant (currently `"0.1.0"`).

#### `Encoder` functions

- `formatMetaLine(_ meta: MetaEnvelope) throws -> String` — renders the canonical `_meta: {...}` JSON-tail line. Alphabetically sorts `filteredBy`, omits `errorNotes` when nil or empty, hand-assembles the top-level JSON object in the locked cross-language key order (`matched_total, returned, filtered_by, latency_ms, redactions, next_cursor, [error_notes]`) so output is byte-equal to the Python + TypeScript sisters for the same input. `next_cursor` is always emitted including as JSON `null` when nil.
- `appendMeta(_ payload: String, _ metaLine: String) -> String` — joins a body and a `_meta:` line with `\n\n`. The joiner is two newlines regardless of whether `payload` is empty.
- `MCPHelpersEncoderError` — typed error surface (currently the single case `invalidJSON`, effectively unreachable but retained as a forward-compatible error vocabulary).

#### Implementation note (locked-key-order)

- Foundation's `JSONEncoder` `KeyedEncodingContainer` does NOT preserve insertion order on Swift 6.0 / Apple Foundation — output key order is observed unstable run-to-run, and `.sortedKeys` produces alphabetical order which does not match the cross-language locked order. `formatMetaLine` therefore hand-assembles the top-level JSON object, using `JSONEncoder` for value-level encoding (strings, arrays) so escape sequences and array element ordering match the platform canonical. Test case "Cross-language byte parity with Python + TypeScript sisters" in `MetaTests.swift` is the load-bearing assertion guarding this contract.

### Motivation
- Per DD-338 Phase E.swift (architect amendment 2026-05-23, substrate-corrected 2026-05-24) — greenfield Swift helper library shipped *before* the W5 Swift wave consumes it, so first-party Swift blade-mcps (`apple-mail-blade-mcp`, `apple-notes-blade-mcp`, and the Swift surface of `stallari-vault` served as `stallari-blade-mcp` via the daemon HTTP MCP per DD-242) can adopt the lib natively without a retrofit step.

### Notes
- Public API frozen during `0.x` series only against breaking changes within a minor; subject to refinement until `1.0.0`.
- The wire contract is specified by Stallari internal design record DD-338 (private; the public summary surfaces gradually as the contract stabilises).
- `1.0.0` cut once consumer blade-mcps have shipped against `0.x` for >30 days with no API churn.
