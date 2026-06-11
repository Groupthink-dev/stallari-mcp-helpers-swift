// Golden parity fixture — byte-locked v0.4.0 wire contract.
//
// The two expected strings below are LITERAL fixtures shared with the
// Python + TypeScript sister repos (identical bytes in their golden
// tests). Do not regenerate them from the code under test; they pin the
// cross-language contract.
//
// The full envelope deliberately carries collation-hostile `filtered_by`
// elements: under the locked raw-code-point collation, "\u{FFFD}b"
// (U+FFFD = 65,533) sorts BEFORE "\u{1F600}a" (U+1F600 = 128,512).
// Swift's default `String <` (Unicode-canonical ordering) and JS's
// default sort (UTF-16 code units — the surrogate D83D would sort the
// emoji first) both diverge here, which is exactly why the comparator is
// explicit. The "é" in both input and expected literals is the
// precomposed U+00E9 (written as an explicit `\u{E9}` escape so no
// editor/normalisation pass can silently decompose it).

import Foundation
import Testing
@testable import MCPHelpers

@Suite("ParityGolden — v0.4.0 byte-locked wire contract")
struct ParityGoldenTests {

    @Test("Full 12-key envelope renders the exact golden bytes")
    func fullEnvelopeGolden() throws {
        let meta = MetaEnvelope(
            matchedTotal: 42,
            returned: 10,
            latencyMs: 7,
            filteredBy: ["zeta", "Alpha", "\u{E9}mile", "\u{1F600}a", "\u{FFFD}b", "a/b"],
            redactions: ["token"],
            nextCursor: "abc/def",
            rowsAffected: 3,
            targetId: "t-1",
            writeDurability: "edge",
            responseTimestamp: "2026-06-12T00:00:00+10:00",
            errorNotes: ["note"],
            domainHints: ["r2": "work", "r1": "family", "r\u{E9}": "home"]
        )
        let line = try formatMetaLine(meta)
        let expected = "_meta: {\"matched_total\":42,\"returned\":10,"
            + "\"filtered_by\":[\"Alpha\",\"a/b\",\"zeta\",\"\u{E9}mile\",\"\u{FFFD}b\",\"\u{1F600}a\"],"
            + "\"latency_ms\":7,\"redactions\":[\"token\"],\"next_cursor\":\"abc/def\","
            + "\"rows_affected\":3,\"target_id\":\"t-1\",\"write_durability\":\"edge\","
            + "\"response_timestamp\":\"2026-06-12T00:00:00+10:00\",\"error_notes\":[\"note\"],"
            + "\"domain_hints\":{\"r1\":\"family\",\"r2\":\"work\",\"r\u{E9}\":\"home\"}}"
        #expect(line == expected)
    }

    @Test("Minimal write-tier envelope renders the exact golden bytes")
    func minimalEnvelopeGolden() throws {
        let meta = MetaEnvelope(
            latencyMs: 1,
            rowsAffected: 1,
            targetId: "x",
            writeDurability: "edge"
        )
        let line = try formatMetaLine(meta)
        let expected = "_meta: {\"filtered_by\":[],\"latency_ms\":1,\"redactions\":[],"
            + "\"next_cursor\":null,\"rows_affected\":1,\"target_id\":\"x\","
            + "\"write_durability\":\"edge\"}"
        #expect(line == expected)
    }
}
