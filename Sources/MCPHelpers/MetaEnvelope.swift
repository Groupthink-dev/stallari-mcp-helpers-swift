// Canonical `_meta: {...}` audit-envelope struct for Stallari-conformant
// Swift MCP servers — sister to the Python `stallari_mcp_helpers`
// `audit_envelope.meta_envelope` and the TypeScript `MetaEnvelope` interface
// at full wire-shape parity.
//
// Wire shape locked per DD-338 Phase A.1 contract; envelope key emission
// order is fixed for cross-language byte parity with the Python canonical:
//   matched_total, returned, filtered_by, latency_ms, redactions,
//   next_cursor, [error_notes]
//
// Field-presence rules:
//   - `matchedTotal`, `returned`, `latencyMs`, `filteredBy`, `redactions`,
//     `nextCursor` — REQUIRED, always present in output. `filteredBy` and
//     `redactions` default to `[]`; `nextCursor` defaults to JSON `null`.
//   - `errorNotes` — OPTIONAL, omitted from output when nil or empty (per
//     Convention #22 graceful degradation; matches Python/TS sisters).
//
// JSON encoding uses snake_case keys via the `CodingKeys` enum below.
//
// Wire-shape parity with the sisters is enforced by `formatMetaLine` in
// `Encoder.swift`, which hand-assembles the top-level JSON object so key
// emission order is byte-locked. Foundation's `KeyedEncodingContainer`
// does NOT preserve insertion order (observed unstable across runs on
// Swift 6.0 Apple Foundation); only `.sortedKeys` is stable, and that
// produces alphabetical order — not the cross-language locked order.
// The hand-rolled `encode(to:)` below still produces *valid* snake_case
// JSON in the locked control-flow order (with `error_notes` omitted when
// nil/empty and `next_cursor` always emitted including as JSON `null`).
// It is exercised by `Codable` round-trips (encode → decode) and any
// consumer who calls `JSONEncoder().encode(envelope)` directly, but it
// is NOT the path that produces the canonical `_meta:` line.

import Foundation

public struct MetaEnvelope: Sendable, Equatable, Codable {
    public let matchedTotal: Int
    public let returned: Int
    public let latencyMs: Int
    public let filteredBy: [String]
    public let redactions: [String]
    public let nextCursor: String?
    public let errorNotes: [String]?

    public init(
        matchedTotal: Int,
        returned: Int,
        latencyMs: Int,
        filteredBy: [String],
        redactions: [String] = [],
        nextCursor: String? = nil,
        errorNotes: [String]? = nil
    ) {
        self.matchedTotal = matchedTotal
        self.returned = returned
        self.latencyMs = latencyMs
        self.filteredBy = filteredBy
        self.redactions = redactions
        self.nextCursor = nextCursor
        self.errorNotes = errorNotes
    }

    enum CodingKeys: String, CodingKey {
        case matchedTotal = "matched_total"
        case returned
        case filteredBy = "filtered_by"
        case latencyMs = "latency_ms"
        case redactions
        case nextCursor = "next_cursor"
        case errorNotes = "error_notes"
    }

    // Hand-rolled encoder locks key emission order to the cross-language
    // contract: matched_total, returned, filtered_by, latency_ms,
    // redactions, next_cursor, [error_notes]. Swift's JSONEncoder without
    // `.sortedKeys` follows CodingKeys declaration order in current Swift
    // versions, but the behaviour is implementation-defined — locking it
    // here removes that fragility.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchedTotal, forKey: .matchedTotal)
        try container.encode(returned, forKey: .returned)
        try container.encode(filteredBy, forKey: .filteredBy)
        try container.encode(latencyMs, forKey: .latencyMs)
        try container.encode(redactions, forKey: .redactions)
        // `next_cursor` is REQUIRED and encodes as JSON `null` when nil.
        // `encodeIfPresent` would omit the key; use the explicit encode
        // overload that preserves null.
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        // `error_notes` is OPTIONAL — omit entirely when nil or empty.
        if let errorNotes, !errorNotes.isEmpty {
            try container.encode(errorNotes, forKey: .errorNotes)
        }
    }
}
