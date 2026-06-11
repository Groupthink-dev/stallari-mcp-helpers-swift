// Canonical `_meta: {...}` line encoder + joiner for Stallari-conformant
// Swift MCP servers.
//
// `formatMetaLine` renders the wire-locked single-line JSON envelope.
// `appendMeta` joins a body and a `_meta:` line with the `\n\n` separator
// expected by the DD-287 assembler-side regex `\n\n_meta: (\{.*\})$`.
//
// IMPLEMENTATION NOTE — key emission order
// =========================================
// Foundation's `JSONEncoder` does NOT guarantee key emission order from a
// `KeyedEncodingContainer`, even when the conforming type's `encode(to:)`
// calls `container.encode(_:forKey:)` in a deterministic sequence. The
// underlying serialiser uses an unordered associative store; output order
// is implementation-defined and observed to vary run-to-run on Swift 6.0
// (Apple-shipped Foundation). The only Foundation knob is `.sortedKeys`,
// which produces alphabetical order — not the cross-language locked
// order our sisters use.
//
// In addition to key-order, Foundation's pretty/compact JSON has two
// further byte-parity hazards vs the Python+TS canonical:
//   - Pretty-printed output uses `"key" : value` (space-padded colon).
//   - Foundation escapes `/` to `\/` in string literals.
// The canonical wire shape uses tight `"key":value` separators and bare
// `/`. We compose the top-level object string by hand to satisfy both.
//
// To meet the byte-parity contract with the Python + TypeScript sister
// libraries, this encoder hand-assembles the top-level JSON object:
// keys are written in the locked order; each VALUE is JSON-encoded via
// `JSONEncoder` (or, for atoms, via a tiny scalar formatter) so that
// string escaping, integer formatting, and nested-array shape are all
// produced by the same Foundation machinery the rest of the platform
// uses — then we post-process value-level strings to unescape `\/` to
// bare `/` (Foundation defaults to escaping it; the canonical does not).
//
// Locked emission order (12 keys — read-tier + write-tier per DD-338 D.1
// + `domain_hints` per v0.4.0 / AUD-04-12):
//   matched_total, returned, filtered_by, latency_ms, redactions,
//   next_cursor, rows_affected, target_id, write_durability,
//   response_timestamp, error_notes, domain_hints
//
// Field-presence rules (omit-when-nil discipline):
//   - `latency_ms`, `filtered_by`, `redactions` — always emitted.
//   - `next_cursor` — always emitted (JSON `null` when nil).
//   - `matched_total`, `returned` — omitted when nil (D.1 write-tier).
//   - `rows_affected`, `target_id`, `write_durability`,
//     `response_timestamp` — OPTIONAL write-tier, omit-when-nil (D.1).
//   - `error_notes` — omit when nil or empty.
//   - `domain_hints` — omit when nil or empty; keys sorted by Unicode
//     code point (see `codePointLess`).
//
// COLLATION NOTE (AUD-04-12): all string sorting in the canonical line
// (`filtered_by` elements, `domain_hints` keys) uses raw Unicode
// code-point order with NO normalisation — Python `sorted()` semantics.
// Swift's default `String <` applies Unicode-canonical ordering, which
// diverges from the locked collation; hence the explicit scalar compare
// in `codePointLess` below.

import Foundation

/// Errors thrown by `formatMetaLine` when value-level JSON encoding fails
/// (effectively unreachable for the value types we encode, but the
/// JSONEncoder API is throwing so we surface a typed error).
public enum MCPHelpersEncoderError: Error, Equatable {
    case invalidJSON
}

/// Locked cross-language collation: lexicographic comparison over the raw
/// Unicode scalar (code-point) values of the two strings, with NO
/// normalisation. This matches Python's `sorted()` on `str` (which
/// compares code points) and the explicit code-point comparator in the
/// TypeScript sister (JS's default sort is UTF-16 code-UNIT order, which
/// also diverges for non-BMP input — both sisters lock to code points).
///
/// Swift's default `String <` is NOT this: it applies Unicode-canonical
/// ordering (and normalisation-aware comparison), which diverges from the
/// locked collation for collation-hostile inputs (e.g. U+FFFD vs
/// U+1F600-prefixed strings, precomposed vs decomposed accents). Hence
/// this explicit scalar compare — use it for every sort that feeds the
/// canonical `_meta:` line.
public func codePointLess(_ lhs: String, _ rhs: String) -> Bool {
    var l = lhs.unicodeScalars.makeIterator()
    var r = rhs.unicodeScalars.makeIterator()
    while true {
        switch (l.next(), r.next()) {
        case (nil, nil):
            return false
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let lv?, let rv?):
            if lv.value != rv.value { return lv.value < rv.value }
        }
    }
}

/// Format a `_meta:` envelope line for appending to a tool payload.
///
/// Single-line JSON; assembler regex `\n\n_meta: (\{.*\})$`. Sorts
/// `filteredBy` by raw Unicode code point (`codePointLess` — the locked
/// cross-language collation, NOT Swift's default `String <`) for
/// byte-equality determinism across call sites that pass the same logical
/// filter set in different orders.
///
/// Field-presence rules (omit-when-nil discipline):
///   - `latency_ms`, `filtered_by`, `redactions`, `next_cursor` — always
///     emitted (`next_cursor` as JSON `null` when nil).
///   - `matched_total`, `returned` — omitted when nil (write-tier callers
///     pass nil; read-tier callers pass concrete Ints).
///   - `rows_affected`, `target_id`, `write_durability`,
///     `response_timestamp` — DD-338 D.1 write-tier; omit-when-nil.
///   - `error_notes` — omitted when nil or empty (Convention #22).
///   - `domain_hints` — omitted when nil or empty (v0.4.0 / AUD-04-12);
///     keys sorted by `codePointLess` when emitted.
///
/// Key emission order matches the Python + TypeScript sister canonicals
/// (12 keys, v0.4.0):
///   matched_total, returned, filtered_by, latency_ms, redactions,
///   next_cursor, rows_affected, target_id, write_durability,
///   response_timestamp, error_notes, domain_hints
public func formatMetaLine(_ meta: MetaEnvelope) throws -> String {
    let sortedFilteredBy = meta.filteredBy.sorted(by: codePointLess)
    let emitErrorNotes = (meta.errorNotes?.isEmpty == false)

    var parts: [String] = []
    if let matchedTotal = meta.matchedTotal {
        parts.append("\"matched_total\":\(matchedTotal)")
    }
    if let returned = meta.returned {
        parts.append("\"returned\":\(returned)")
    }
    parts.append("\"filtered_by\":\(try encodeStringArray(sortedFilteredBy))")
    parts.append("\"latency_ms\":\(meta.latencyMs)")
    parts.append("\"redactions\":\(try encodeStringArray(meta.redactions))")
    if let nextCursor = meta.nextCursor {
        parts.append("\"next_cursor\":\(try encodeJSONString(nextCursor))")
    } else {
        parts.append("\"next_cursor\":null")
    }
    if let rowsAffected = meta.rowsAffected {
        parts.append("\"rows_affected\":\(rowsAffected)")
    }
    if let targetId = meta.targetId {
        parts.append("\"target_id\":\(try encodeJSONString(targetId))")
    }
    if let writeDurability = meta.writeDurability {
        parts.append("\"write_durability\":\(try encodeJSONString(writeDurability))")
    }
    if let responseTimestamp = meta.responseTimestamp {
        parts.append("\"response_timestamp\":\(try encodeJSONString(responseTimestamp))")
    }
    if emitErrorNotes, let notes = meta.errorNotes {
        parts.append("\"error_notes\":\(try encodeStringArray(notes))")
    }
    if let domainHints = meta.domainHints, !domainHints.isEmpty {
        // Hand-assemble the object so key order is the locked code-point
        // collation (Foundation's dictionary encoding has no usable order).
        let sortedKeys = domainHints.keys.sorted(by: codePointLess)
        var pairs: [String] = []
        pairs.reserveCapacity(sortedKeys.count)
        for key in sortedKeys {
            // Force-unwrap is safe — keys come from the dictionary itself.
            pairs.append("\(try encodeJSONString(key)):\(try encodeJSONString(domainHints[key]!))")
        }
        parts.append("\"domain_hints\":{" + pairs.joined(separator: ",") + "}")
    }
    return "_meta: {" + parts.joined(separator: ",") + "}"
}

/// Append a `_meta` envelope line to an existing text payload using the
/// canonical `\n\n` separator. Use this helper at every tool-handler site;
/// do not inline the concatenation. The joiner is two newlines regardless
/// of whether `payload` is empty — the assembler-side regex
/// `\n\n_meta: (\{.*\})$` still matches at end-of-string in the empty-body
/// case.
public func appendMeta(_ payload: String, _ metaLine: String) -> String {
    payload + "\n\n" + metaLine
}

// MARK: - Internal scalar helpers

/// Encode a single `String` as a JSON string literal (including the
/// surrounding double-quotes), using Foundation's `JSONEncoder` so escape
/// sequences match the platform's canonical representation. Post-processes
/// Foundation's default `\/` slash-escape back to bare `/` for cross-
/// language byte parity with the Python + TypeScript sisters (both of
/// which emit bare `/`).
private func encodeJSONString(_ value: String) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(value)
    guard let s = String(data: data, encoding: .utf8) else {
        throw MCPHelpersEncoderError.invalidJSON
    }
    return s.replacingOccurrences(of: "\\/", with: "/")
}

/// Encode an array of strings as a JSON array literal. Foundation
/// preserves array element order (unlike object keyed-container order),
/// so a single `JSONEncoder.encode` call suffices. Post-processes the
/// slash-escape sequence (`\/` → `/`) for cross-language byte parity.
private func encodeStringArray(_ value: [String]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(value)
    guard let s = String(data: data, encoding: .utf8) else {
        throw MCPHelpersEncoderError.invalidJSON
    }
    return s.replacingOccurrences(of: "\\/", with: "/")
}
