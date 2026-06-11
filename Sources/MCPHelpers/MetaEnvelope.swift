// Canonical `_meta: {...}` audit-envelope struct for Stallari-conformant
// Swift MCP servers — sister to the Python `stallari_mcp_helpers`
// `audit_envelope.meta_envelope` and the TypeScript `MetaEnvelope` interface
// at full wire-shape parity.
//
// Wire shape locked per DD-338 Phase A.1 + Phase D.1 contract, extended to
// the 12-key v0.4.0 cross-language contract (AUD-04-12). Envelope key
// emission order (locked across read + write tier):
//   matched_total, returned, filtered_by, latency_ms, redactions,
//   next_cursor, rows_affected, target_id, write_durability,
//   response_timestamp, error_notes, domain_hints
//
// Field-presence rules (DD-338 D.1 — relaxed read-tier + new write-tier):
//   - `latencyMs`, `filteredBy`, `redactions` — always present in output.
//     `filteredBy` and `redactions` default to `[]`.
//   - `nextCursor` — always present in output (encodes as JSON `null` when
//     nil; matches Python/TS sister discipline).
//   - `matchedTotal`, `returned` — OPTIONAL since D.1 (omit-when-nil). Pure
//     write-tier tool calls omit both; read-tier callers continue to pass
//     concrete values.
//   - `errorNotes` — OPTIONAL, omit when nil or empty (Convention #22).
//   - `rowsAffected`, `targetId`, `writeDurability`, `responseTimestamp` —
//     OPTIONAL write-tier fields (DD-338 D.1). Omit-when-nil. Canonical
//     `writeDurability` values: "edge" | "central" | "replicated" (typed as
//     plain `String?` for forward-compatibility — additional vocab terms
//     added later won't break decoding).
//   - `domainHints` — OPTIONAL (v0.4.0 / AUD-04-12). Omit entirely when nil
//     or empty. When emitted, object keys are sorted by raw Unicode
//     code-point value (Python `sorted()` semantics) — see the
//     `codePointLess` comparator in `Encoder.swift`.
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
// JSON in the locked control-flow order (with omit-when-nil discipline
// honoured for every optional field, and `next_cursor` always emitted
// including as JSON `null`). It is exercised by `Codable` round-trips
// (encode → decode) and any consumer who calls `JSONEncoder().encode(envelope)`
// directly, but it is NOT the path that produces the canonical `_meta:` line.

import Foundation

public struct MetaEnvelope: Sendable, Equatable, Codable {
    public let matchedTotal: Int?
    public let returned: Int?
    public let latencyMs: Int
    public let filteredBy: [String]
    public let redactions: [String]
    public let nextCursor: String?
    public let rowsAffected: Int?
    public let targetId: String?
    public let writeDurability: String?
    public let responseTimestamp: String?
    public let errorNotes: [String]?
    public let domainHints: [String: String]?

    public init(
        matchedTotal: Int? = nil,
        returned: Int? = nil,
        latencyMs: Int,
        filteredBy: [String] = [],
        redactions: [String] = [],
        nextCursor: String? = nil,
        rowsAffected: Int? = nil,
        targetId: String? = nil,
        writeDurability: String? = nil,
        responseTimestamp: String? = nil,
        errorNotes: [String]? = nil,
        domainHints: [String: String]? = nil
    ) {
        self.matchedTotal = matchedTotal
        self.returned = returned
        self.latencyMs = latencyMs
        self.filteredBy = filteredBy
        self.redactions = redactions
        self.nextCursor = nextCursor
        self.rowsAffected = rowsAffected
        self.targetId = targetId
        self.writeDurability = writeDurability
        self.responseTimestamp = responseTimestamp
        self.errorNotes = errorNotes
        self.domainHints = domainHints
    }

    enum CodingKeys: String, CodingKey {
        case matchedTotal = "matched_total"
        case returned
        case filteredBy = "filtered_by"
        case latencyMs = "latency_ms"
        case redactions
        case nextCursor = "next_cursor"
        case rowsAffected = "rows_affected"
        case targetId = "target_id"
        case writeDurability = "write_durability"
        case responseTimestamp = "response_timestamp"
        case errorNotes = "error_notes"
        case domainHints = "domain_hints"
    }

    // Hand-rolled encoder locks key emission order to the cross-language
    // contract (12 keys, v0.4.0):
    //   matched_total, returned, filtered_by, latency_ms, redactions,
    //   next_cursor, rows_affected, target_id, write_durability,
    //   response_timestamp, error_notes, domain_hints
    //
    // Omit-when-nil discipline matches `formatMetaLine` exactly. Note that
    // the canonical `_meta:` line is produced by `formatMetaLine` (a
    // hand-assembled string concatenation) — this `encode(to:)`
    // implementation is exercised only by `Codable` round-trips and direct
    // `JSONEncoder().encode(envelope)` calls and is NOT byte-equal to the
    // canonical line (Foundation re-orders keys, adds spaces around colons,
    // escapes forward slashes — see Encoder.swift implementation note).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(matchedTotal, forKey: .matchedTotal)
        try container.encodeIfPresent(returned, forKey: .returned)
        try container.encode(filteredBy, forKey: .filteredBy)
        try container.encode(latencyMs, forKey: .latencyMs)
        try container.encode(redactions, forKey: .redactions)
        // `next_cursor` is always present; encode null when nil.
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        try container.encodeIfPresent(rowsAffected, forKey: .rowsAffected)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        try container.encodeIfPresent(writeDurability, forKey: .writeDurability)
        try container.encodeIfPresent(responseTimestamp, forKey: .responseTimestamp)
        // `error_notes` is OPTIONAL — omit entirely when nil or empty.
        if let errorNotes, !errorNotes.isEmpty {
            try container.encode(errorNotes, forKey: .errorNotes)
        }
        // `domain_hints` is OPTIONAL — omit entirely when nil or empty
        // (same discipline as `error_notes`). Note: the canonical
        // `formatMetaLine` path emits its keys sorted by Unicode
        // code point; this Codable path delegates to Foundation's
        // dictionary encoding (key order unspecified) and is exercised
        // only by round-trips.
        if let domainHints, !domainHints.isEmpty {
            try container.encode(domainHints, forKey: .domainHints)
        }
    }
}
