# Changelog

All notable changes to `MCPHelpers` (Swift) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-06-12

DD-386 helper-lib hardening — locks the Swift sibling to the v0.4.0 cross-language contract just shipped by the Python canonical [`stallari-mcp-helpers`](https://pypi.org/project/stallari-mcp-helpers/) and the TypeScript sibling. Fixes AUD-04-12 (11-key envelope + wrong collation), AUD-04-13 (lint bare-name trust + false over-declared), and adds the AUD-04-08 canonical HTTP transport-policy surface.

> **Parity correction:** v0.3.0's claimed cross-language parity was inaccurate — this package emitted an 11-key envelope (missing `domain_hints`) and sorted `filtered_by` with Swift's default Unicode-canonical `String <` rather than the locked raw code-point collation. Byte parity across the trio holds from v0.4.0 onward.

### Added

- `MetaEnvelope.domainHints: [String: String]?` (wire: `domain_hints`) — 12-key parity with the Python/TS sisters (AUD-04-12). Omit-when-nil-or-empty (same discipline as `error_notes`). When emitted, object keys are sorted by raw Unicode code point. Locked 12-key emission order now ends `..., error_notes, domain_hints`.
- `codePointLess(_:_:)` — public locked-collation comparator: lexicographic over raw Unicode scalar values, no normalisation (Python `sorted()` semantics). Swift's default `String <` applies Unicode-canonical ordering, which diverges from the locked collation — `formatMetaLine` now sorts `filtered_by` and `domain_hints` keys with this comparator. Public so blades can reuse it.
- `Sources/MCPHelpers/Transport.swift` — canonical HTTP transport policy (AUD-04-08), sister to the Python/TS v0.4.0 transport modules. Token-absent HTTP REFUSES to serve (never warn-and-serve unauthenticated); wildcard binds (`0.0.0.0`, `::`, `[::]`, empty) never permitted; non-loopback binds require `{PREFIX}_MCP_ALLOW_NONLOOPBACK` exactly `"true"`. Surface: `TransportPolicyError` (operator-actionable descriptions, never containing token material), `HTTPTransportConfig`, `strictEnvBool(_:)`, `resolveHTTPTransport(envPrefix:defaultPort:environment:tokenVariable:)`, and `validateBearer(authorizationHeader:expectedToken:)` (case-insensitive `Bearer` scheme, constant-time SHA-256-digest compare; callers must enforce it on WebSocket upgrades too — AUD-04-31).
- `Tests/MCPHelpersTests/ParityGoldenTests.swift` — golden parity fixture asserting `formatMetaLine` renders the exact byte-locked v0.4.0 wire strings (identical literals exist in the Python + TS sibling repos), including the collation-hostile `U+FFFD` vs `U+1F600` `filtered_by` pair and non-ASCII `domain_hints` keys.
- `Tests/MCPHelpersTests/TransportTests.swift` — full refusal matrix + bearer-validation suite.

### Changed

- **Lint (S-AUD-001, AUD-04-13):** `canonicalEmitNames` reduced to `["appendMeta"]`. `makeResultWithMeta` is a per-blade hand-rolled wrapper, not a library symbol — trusting it by bare name let a drifted wrapper that never calls `appendMeta` lint "structured" (the exact over-declaration S-AUD-001 exists to catch). A blade's `makeResultWithMeta` (or any wrapper) now satisfies the lint only when the resolver finds its actual body and that body transitively calls `appendMeta`.
- **Lint wrapper resolution:** `functionIsCanonical` falls back to the cross-module `typeMethodsIndex` when no free function matches — wrappers that are static/instance methods on utility types now resolve.
- **Lint tri-state emission decision:** `bodyEmits(registration:)` returns `Bool?`. For switch-dispatch registrations, an unresolvable handler property type, missing method, or bodyless method returns `nil` (resolution failure, not proof of non-emission) and surfaces as an `indeterminate` verdict with an actionable detail — previously these produced a false `over-declared`.
- `MCPHelpers.version` bumped to `"0.4.0"`.

### Notes

- `formatMetaLine` output is byte-identical to v0.3.0 for envelopes without `domainHints` whose `filteredBy` elements are ASCII-only (the overwhelmingly common case) — the collation change only affects non-ASCII/collation-hostile inputs, which is precisely where v0.3.0 diverged from the sisters.

## [0.3.0] - 2026-05-24

DD-338 Phase D.1 Swift sibling — additive extension of `MetaEnvelope` for write-tier audit fields. Sister to the Python sibling [`stallari-mcp-helpers` 0.3.0](https://pypi.org/project/stallari-mcp-helpers/) and the TypeScript sibling at the same JSON output shape (byte-parity confirmed via shared kitchen-sink fixture).

### Added

- `MetaEnvelope` write-tier optional fields (all omit-when-nil):
  - `rowsAffected: Int?` (wire: `rows_affected`) — rows / nodes / records affected by the write.
  - `targetId: String?` (wire: `target_id`) — server-side identity of the primary target of the write (note ID, row PK, etc.).
  - `writeDurability: String?` (wire: `write_durability`) — canonical vocab `"edge" | "central" | "replicated"`. Typed as plain `String?` for forward-compat with vocab extensions.
  - `responseTimestamp: String?` (wire: `response_timestamp`) — ISO8601 timestamp of the write commit.
- `formatMetaLine` extended with locked write-tier key emission order. Canonical key order (read + write):
  `matched_total, returned, filtered_by, latency_ms, redactions, next_cursor, rows_affected, target_id, write_durability, response_timestamp, error_notes`
- `Tests/MCPHelpersTests/MetaTests.swift` — extended to 26 Swift Testing cases. Adds per-field presence/absence cases, write-tier-only envelope, kitchen-sink read+write envelope, key-order substring index assertion, cross-language byte-parity fixture extended for D.1, regex contract extended for D.1, Codable round-trip extended for D.1, and a backwards-compatibility case mirroring the exact v0.2.0 apple-notes/apple-mail call shape.

### Changed

- `MetaEnvelope.matchedTotal` and `MetaEnvelope.returned` relaxed from required `Int` to optional `Int?` (omit-when-nil). Pure write-tier callers omit both; read-tier callers continue to pass concrete values. Backwards-compatible — existing call sites that pass keyword arguments compile unchanged.
- `Encoder.swift` internal scalar helpers (`encodeJSONString`, `encodeStringArray`) now post-process Foundation's default `\/` slash-escape back to bare `/` for cross-language byte parity with the Python + TypeScript sisters. v0.2.0 fixtures never exercised slash-containing strings; D.1 timestamps and arbitrary write-tier IDs may.
- `MCPHelpers.version` bumped to `"0.3.0"`.

### Notes

- Backwards-compatible — `apple-notes-blade-mcp` and `apple-mail-blade-mcp` consumer call sites unchanged; old read-tier envelope bytes identical to v0.2.0 output (`backwardsCompatibility` test pins this).
- Convention #23 reader-audit scope on this phase: `apple-notes-blade-mcp`, `apple-mail-blade-mcp`, and the daemon-side `_meta:` assembler regex consumer in stallari-harness/stallari-vault. None of these readers parse beyond the canonical regex envelope today; the additive D.1 fields are transparent to all current consumers.

## [0.2.0] - 2026-05-24

DD-338 Phase B Swift sibling — adds the S-AUD-001 audit-surface honesty linter to the `MCPHelpers` package + a `stallari-mcp-lint` console-script executable target. Sister to the Python sibling [`stallari_mcp_helpers.lint`](https://pypi.org/project/stallari-mcp-helpers/) and the TS sibling at the same JSON output shape (byte-parity after canonical-JSON normalisation).

### Added

- `Sources/MCPHelpers/Lint.swift` — SwiftSyntax-based static linter. Walks a blade-mcp Swift source tree, identifies tool registrations across three patterns (switch-dispatch ToolRegistry, FastMCP-style decorator, imperative `server.addTool(name:) { ... }`), and verifies each tool's emission graph reaches a canonical emit name (`appendMeta` or `makeResultWithMeta`) within 3 wrapper hops.
- Public API surface: `lintBlade(bladeSourceRoot:catalogEntry:)`, `LintResult`, `ToolVerdict`, `AuditSurfaceVerdict`, `LintSummary`, constants `lintRuleID = "S-AUD-001"`, `canonicalEmitNames`, `maxResolutionDepth = 3`.
- `LintResult.canonicalJSON()` — renders the verdict envelope as JSON byte-identical to the Python sister's `json.dumps(result.to_dict(), indent=2, sort_keys=True)`. Built on `JSONSerialization` with `.sortedKeys` + `.prettyPrinted` then normalised to Python-style key/value separator (`": "` not `" : "`) and bare-`/` (not `\/`). Hand-assembled rather than `JSONEncoder.encode(self)` because Foundation's `KeyedEncodingContainer` key emission order is implementation-defined — see `[[feedback_swift_jsonencoder_key_order]]`.
- `Sources/StallariMCPLintCLI/main.swift` — `stallari-mcp-lint` executable target. CLI: `stallari-mcp-lint <blade-source-root> --catalog <catalog.json> [--output <sidecar.json>] [--strict]`. `--strict` exits non-zero (1) on any over-declared/under-declared verdict (indeterminate does NOT trip strict mode — explicit "lint can't tell" rather than "lint says wrong").
- `Tests/MCPHelpersTests/LintTests.swift` — 14 Swift Testing cases (L1–L11 spec mirror + FastMCP decorator + addTool + garbage-file resilience + public-constants guard). Synthesises tiny on-disk blade fixtures per case.

### Changed

- `MCPHelpers.version` bumped to `"0.2.0"`.
- `Package.swift` — adds `swift-syntax` SPM dependency (pinned `from: "600.0.0"` matching stallari-harness Tools/source-lint) and `stallari-mcp-lint` executable product/target.

### Verified

- 31/31 tests pass (`swift test`).
- Smoke against `apple-notes-blade-mcp` (5 tools) — 0 over-declared, 0 under-declared, 5 match.
- Smoke against `apple-mail-blade-mcp` (11 tools) — 0 over-declared, 0 under-declared, 11 match.

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
