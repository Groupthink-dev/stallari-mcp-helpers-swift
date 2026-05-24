// Comprehensive coverage for `MetaEnvelope` + `formatMetaLine` +
// `appendMeta`. Test "Cross-language byte parity" is the load-bearing
// determinism + key-order + separator guard rolled into one — if it
// passes, the Swift `formatMetaLine` output is byte-equal to the Python +
// TypeScript sisters for the same input.
//
// DD-338 Phase D.1 extension — adds write-tier optional fields
// (rows_affected, target_id, write_durability, response_timestamp) and
// exercises matched_total/returned being omittable for pure write calls.

import Foundation
import Testing
@testable import MCPHelpers

@Suite("MetaEnvelope encoding")
struct MetaTests {

    // MARK: - Required-fields-only (read-tier baseline)

    @Test("Read-tier baseline — matched_total/returned/latency_ms present, redactions empty, next_cursor null")
    func requiredFieldsOnly() throws {
        let meta = MetaEnvelope(matchedTotal: 10, returned: 10, latencyMs: 42, filteredBy: [])
        let line = try formatMetaLine(meta)
        #expect(line.hasPrefix("_meta: "))
        #expect(line.contains("\"matched_total\":10"))
        #expect(line.contains("\"returned\":10"))
        #expect(line.contains("\"latency_ms\":42"))
        #expect(line.contains("\"filtered_by\":[]"))
        #expect(line.contains("\"redactions\":[]"))
        #expect(line.contains("\"next_cursor\":null"))
        #expect(!line.contains("error_notes"))
        // None of the new write-tier fields should leak in when not set.
        #expect(!line.contains("rows_affected"))
        #expect(!line.contains("target_id"))
        #expect(!line.contains("write_durability"))
        #expect(!line.contains("response_timestamp"))
    }

    // MARK: - filteredBy sorting

    @Test("filteredBy is alphabetically sorted in output")
    func filteredBySorted() throws {
        let meta = MetaEnvelope(
            matchedTotal: 1,
            returned: 1,
            latencyMs: 10,
            filteredBy: ["scope=work", "limit=10", "active=true"]
        )
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"filtered_by\":[\"active=true\",\"limit=10\",\"scope=work\"]"))
    }

    // MARK: - redactions populated

    @Test("redactions populated emits the array")
    func redactionsPopulated() throws {
        let meta = MetaEnvelope(
            matchedTotal: 5,
            returned: 5,
            latencyMs: 17,
            filteredBy: [],
            redactions: ["pii_email"]
        )
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"redactions\":[\"pii_email\"]"))
    }

    // MARK: - errorNotes omission

    @Test("errorNotes nil → key absent")
    func errorNotesNilAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1, filteredBy: [], errorNotes: nil)
        let line = try formatMetaLine(meta)
        #expect(!line.contains("error_notes"))
    }

    @Test("errorNotes empty array → key absent")
    func errorNotesEmptyAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1, filteredBy: [], errorNotes: [])
        let line = try formatMetaLine(meta)
        #expect(!line.contains("error_notes"))
    }

    @Test("errorNotes populated emits the array")
    func errorNotesPopulated() throws {
        let meta = MetaEnvelope(
            matchedTotal: 1,
            returned: 1,
            latencyMs: 1,
            filteredBy: [],
            errorNotes: ["warn1", "warn2"]
        )
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"error_notes\":[\"warn1\",\"warn2\"]"))
    }

    // MARK: - nextCursor

    @Test("nextCursor is a string → emitted as JSON string")
    func nextCursorString() throws {
        let meta = MetaEnvelope(
            matchedTotal: 100,
            returned: 10,
            latencyMs: 50,
            filteredBy: [],
            nextCursor: "cursor_abc"
        )
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"next_cursor\":\"cursor_abc\""))
    }

    @Test("nextCursor nil → emitted as literal null (not omitted)")
    func nextCursorNilEmitsNull() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1, filteredBy: [], nextCursor: nil)
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"next_cursor\":null"))
    }

    // MARK: - Determinism

    @Test("Same input → identical output across runs (byte-equality determinism)")
    func deterministicOutput() throws {
        let meta = MetaEnvelope(
            matchedTotal: 7,
            returned: 3,
            latencyMs: 12,
            filteredBy: ["b", "a", "c"],
            redactions: ["r1"],
            nextCursor: "cur",
            errorNotes: ["e1"]
        )
        let line1 = try formatMetaLine(meta)
        let line2 = try formatMetaLine(meta)
        let line3 = try formatMetaLine(meta)
        #expect(line1 == line2)
        #expect(line2 == line3)
    }

    // MARK: - Strict separators

    @Test("Output uses tight JSON separators (no spaces around , or :)")
    func strictSeparators() throws {
        let meta = MetaEnvelope(
            matchedTotal: 1,
            returned: 1,
            latencyMs: 1,
            filteredBy: ["x"],
            redactions: ["y"],
            nextCursor: "z"
        )
        let line = try formatMetaLine(meta)
        // The JSON body lives after the `_meta: ` (six-char prefix); the
        // space after the colon is part of the literal prefix, not the
        // JSON. The JSON itself must have no space after `,` or `:`.
        let jsonPart = String(line.dropFirst("_meta: ".count))
        #expect(!jsonPart.contains(", "))
        #expect(!jsonPart.contains(": "))
    }

    // MARK: - Cross-language byte parity (LOAD-BEARING — read-tier baseline)

    @Test("Cross-language byte parity (read-tier baseline) with Python + TypeScript sisters")
    func crossLanguageByteParity() throws {
        let meta = MetaEnvelope(
            matchedTotal: 42,
            returned: 10,
            latencyMs: 234,
            filteredBy: ["scope=work", "limit=10"],
            redactions: [],
            nextCursor: nil
        )
        let line = try formatMetaLine(meta)
        let expected = #"_meta: {"matched_total":42,"returned":10,"filtered_by":["limit=10","scope=work"],"latency_ms":234,"redactions":[],"next_cursor":null}"#
        #expect(line == expected)
    }

    // MARK: - DD-338 D.1 — write-tier fields

    @Test("rows_affected omitted when nil")
    func rowsAffectedNilAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1)
        let line = try formatMetaLine(meta)
        #expect(!line.contains("rows_affected"))
    }

    @Test("rows_affected emitted as integer when set")
    func rowsAffectedPresent() throws {
        let meta = MetaEnvelope(latencyMs: 5, rowsAffected: 3)
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"rows_affected\":3"))
    }

    @Test("target_id omitted when nil")
    func targetIdNilAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1)
        let line = try formatMetaLine(meta)
        #expect(!line.contains("target_id"))
    }

    @Test("target_id emitted as JSON string when set")
    func targetIdPresent() throws {
        let meta = MetaEnvelope(latencyMs: 5, targetId: "note-xyz")
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"target_id\":\"note-xyz\""))
    }

    @Test("write_durability omitted when nil")
    func writeDurabilityNilAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1)
        let line = try formatMetaLine(meta)
        #expect(!line.contains("write_durability"))
    }

    @Test("write_durability emitted as JSON string when set (canonical 'edge')")
    func writeDurabilityEdge() throws {
        let meta = MetaEnvelope(latencyMs: 5, writeDurability: "edge")
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"write_durability\":\"edge\""))
    }

    @Test("write_durability emitted as JSON string when set (canonical 'central')")
    func writeDurabilityCentral() throws {
        let meta = MetaEnvelope(latencyMs: 5, writeDurability: "central")
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"write_durability\":\"central\""))
    }

    @Test("write_durability emitted as JSON string when set (canonical 'replicated')")
    func writeDurabilityReplicated() throws {
        let meta = MetaEnvelope(latencyMs: 5, writeDurability: "replicated")
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"write_durability\":\"replicated\""))
    }

    @Test("response_timestamp omitted when nil")
    func responseTimestampNilAbsent() throws {
        let meta = MetaEnvelope(matchedTotal: 1, returned: 1, latencyMs: 1)
        let line = try formatMetaLine(meta)
        #expect(!line.contains("response_timestamp"))
    }

    @Test("response_timestamp emitted as JSON string when set (ISO8601)")
    func responseTimestampPresent() throws {
        let meta = MetaEnvelope(
            latencyMs: 5,
            responseTimestamp: "2026-05-24T12:34:56Z"
        )
        let line = try formatMetaLine(meta)
        #expect(line.contains("\"response_timestamp\":\"2026-05-24T12:34:56Z\""))
    }

    // MARK: - DD-338 D.1 — write-tier only (matched_total/returned omitted)

    @Test("Pure write-tier call — matched_total and returned omitted, write fields emitted")
    func writeTierOnly() throws {
        let meta = MetaEnvelope(
            latencyMs: 8,
            rowsAffected: 1,
            targetId: "note-abc",
            writeDurability: "edge",
            responseTimestamp: "2026-05-24T01:02:03Z"
        )
        let line = try formatMetaLine(meta)
        #expect(!line.contains("matched_total"))
        #expect(!line.contains("returned"))
        // Always-present fields still there.
        #expect(line.contains("\"latency_ms\":8"))
        #expect(line.contains("\"filtered_by\":[]"))
        #expect(line.contains("\"redactions\":[]"))
        #expect(line.contains("\"next_cursor\":null"))
        // Write-tier fields all present.
        #expect(line.contains("\"rows_affected\":1"))
        #expect(line.contains("\"target_id\":\"note-abc\""))
        #expect(line.contains("\"write_durability\":\"edge\""))
        #expect(line.contains("\"response_timestamp\":\"2026-05-24T01:02:03Z\""))
    }

    // MARK: - DD-338 D.1 — key-order invariant (load-bearing)

    @Test("Canonical key emission order — kitchen-sink read+write envelope")
    func canonicalKeyOrderKitchenSink() throws {
        let meta = MetaEnvelope(
            matchedTotal: 100,
            returned: 25,
            latencyMs: 42,
            filteredBy: ["scope=work"],
            redactions: ["pii_email"],
            nextCursor: "cur_abc",
            rowsAffected: 3,
            targetId: "note-xyz",
            writeDurability: "central",
            responseTimestamp: "2026-05-24T00:00:00Z",
            errorNotes: ["warn1"]
        )
        let line = try formatMetaLine(meta)
        // Substring index walk — each key must appear strictly after the
        // previous one in the canonical order.
        let keys = [
            "\"matched_total\"",
            "\"returned\"",
            "\"filtered_by\"",
            "\"latency_ms\"",
            "\"redactions\"",
            "\"next_cursor\"",
            "\"rows_affected\"",
            "\"target_id\"",
            "\"write_durability\"",
            "\"response_timestamp\"",
            "\"error_notes\"",
        ]
        var lastIdx = line.startIndex
        for key in keys {
            guard let r = line.range(of: key, range: lastIdx..<line.endIndex) else {
                Issue.record("Key \(key) missing or out-of-order in: \(line)")
                return
            }
            lastIdx = r.upperBound
        }
    }

    // MARK: - DD-338 D.1 — cross-language byte parity (write-tier kitchen sink)

    @Test("Cross-language byte parity — DD-338 D.1 kitchen-sink envelope")
    func crossLanguageByteParityWriteTier() throws {
        let meta = MetaEnvelope(
            matchedTotal: 100,
            returned: 25,
            latencyMs: 42,
            filteredBy: ["scope=work"],
            redactions: ["pii_email"],
            nextCursor: "cur_abc",
            rowsAffected: 3,
            targetId: "note-xyz",
            writeDurability: "central",
            responseTimestamp: "2026-05-24T00:00:00Z",
            errorNotes: ["warn1"]
        )
        let line = try formatMetaLine(meta)
        let expected = #"_meta: {"matched_total":100,"returned":25,"filtered_by":["scope=work"],"latency_ms":42,"redactions":["pii_email"],"next_cursor":"cur_abc","rows_affected":3,"target_id":"note-xyz","write_durability":"central","response_timestamp":"2026-05-24T00:00:00Z","error_notes":["warn1"]}"#
        #expect(line == expected)
    }

    @Test("Cross-language byte parity — DD-338 D.1 write-only envelope")
    func crossLanguageByteParityWriteOnly() throws {
        let meta = MetaEnvelope(
            latencyMs: 8,
            rowsAffected: 1,
            targetId: "note-abc",
            writeDurability: "edge",
            responseTimestamp: "2026-05-24T01:02:03Z"
        )
        let line = try formatMetaLine(meta)
        let expected = #"_meta: {"filtered_by":[],"latency_ms":8,"redactions":[],"next_cursor":null,"rows_affected":1,"target_id":"note-abc","write_durability":"edge","response_timestamp":"2026-05-24T01:02:03Z"}"#
        #expect(line == expected)
    }

    // MARK: - appendMeta

    @Test("appendMeta joins body and meta line with \\n\\n")
    func appendMetaJoiner() {
        let joined = appendMeta("body text", "_meta: {\"k\":1}")
        #expect(joined == "body text\n\n_meta: {\"k\":1}")
    }

    @Test("appendMeta with empty body still emits \\n\\n joiner")
    func appendMetaEmptyBody() {
        let joined = appendMeta("", "_meta: {\"k\":1}")
        #expect(joined == "\n\n_meta: {\"k\":1}")
    }

    // MARK: - Regex contract (extended for D.1)

    @Test("formatMetaLine output matches the assembler-side regex contract — read + write + mixed")
    func regexContract() throws {
        let regex = try Regex(#"^_meta: (\{.*\})$"#)
        let combinations: [MetaEnvelope] = [
            // Read-tier minimal.
            MetaEnvelope(matchedTotal: 0, returned: 0, latencyMs: 0, filteredBy: []),
            // Read-tier with everything.
            MetaEnvelope(
                matchedTotal: 1,
                returned: 1,
                latencyMs: 1,
                filteredBy: ["a"],
                redactions: ["r"],
                nextCursor: "n"
            ),
            // Read-tier with errorNotes.
            MetaEnvelope(
                matchedTotal: 99,
                returned: 50,
                latencyMs: 1000,
                filteredBy: [],
                errorNotes: ["e1", "e2"]
            ),
            // Read-tier kitchen sink.
            MetaEnvelope(
                matchedTotal: 5,
                returned: 5,
                latencyMs: 5,
                filteredBy: ["x=1", "y=2"],
                redactions: ["pii"],
                nextCursor: "next",
                errorNotes: ["warn"]
            ),
            // D.1 write-tier only.
            MetaEnvelope(
                latencyMs: 1,
                rowsAffected: 1,
                targetId: "t",
                writeDurability: "edge",
                responseTimestamp: "2026-05-24T00:00:00Z"
            ),
            // D.1 mixed read + write.
            MetaEnvelope(
                matchedTotal: 1,
                returned: 1,
                latencyMs: 1,
                filteredBy: ["k=v"],
                redactions: ["r"],
                nextCursor: "cur",
                rowsAffected: 2,
                targetId: "tgt",
                writeDurability: "replicated",
                responseTimestamp: "2026-05-24T12:00:00Z",
                errorNotes: ["warn"]
            ),
        ]
        for meta in combinations {
            let line = try formatMetaLine(meta)
            let match = try regex.wholeMatch(in: line)
            #expect(match != nil, "Line failed regex contract: \(line)")
        }
    }

    // MARK: - Codable round-trip (decoding sanity, D.1 extended)

    @Test("MetaEnvelope round-trips via Codable — read + write tier")
    func codableRoundTrip() throws {
        let original = MetaEnvelope(
            matchedTotal: 11,
            returned: 4,
            latencyMs: 88,
            filteredBy: ["c", "a", "b"],
            redactions: ["r1", "r2"],
            nextCursor: "abc",
            rowsAffected: 7,
            targetId: "note-1",
            writeDurability: "edge",
            responseTimestamp: "2026-05-24T00:00:00Z",
            errorNotes: ["x"]
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MetaEnvelope.self, from: data)
        // filteredBy is preserved as-encoded (the *encoder*-side `formatMetaLine`
        // sorts it; raw `JSONEncoder.encode` does not). So compare element-wise.
        #expect(decoded.matchedTotal == original.matchedTotal)
        #expect(decoded.returned == original.returned)
        #expect(decoded.latencyMs == original.latencyMs)
        #expect(decoded.filteredBy == original.filteredBy)
        #expect(decoded.redactions == original.redactions)
        #expect(decoded.nextCursor == original.nextCursor)
        #expect(decoded.rowsAffected == original.rowsAffected)
        #expect(decoded.targetId == original.targetId)
        #expect(decoded.writeDurability == original.writeDurability)
        #expect(decoded.responseTimestamp == original.responseTimestamp)
        #expect(decoded.errorNotes == original.errorNotes)
    }

    @Test("MetaEnvelope round-trips via Codable — write-tier only (matched_total/returned absent)")
    func codableRoundTripWriteOnly() throws {
        let original = MetaEnvelope(
            latencyMs: 4,
            rowsAffected: 1,
            targetId: "t",
            writeDurability: "central"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MetaEnvelope.self, from: data)
        #expect(decoded.matchedTotal == nil)
        #expect(decoded.returned == nil)
        #expect(decoded.latencyMs == 4)
        #expect(decoded.rowsAffected == 1)
        #expect(decoded.targetId == "t")
        #expect(decoded.writeDurability == "central")
        #expect(decoded.responseTimestamp == nil)
    }

    // MARK: - Backwards compatibility (DD-338 D.1)

    @Test("Backwards compatibility — v0.2.0-style read-tier MetaEnvelope still produces valid envelope")
    func backwardsCompatibility() throws {
        // Mirror the exact call shape used by apple-notes-blade-mcp /
        // apple-mail-blade-mcp prior to D.1 (no write-tier fields, all
        // read-tier required-then fields populated).
        let meta = MetaEnvelope(
            matchedTotal: 50,
            returned: 10,
            latencyMs: 120,
            filteredBy: ["limit=10", "scope=inbox"],
            redactions: [],
            nextCursor: "page_2",
            errorNotes: nil
        )
        let line = try formatMetaLine(meta)
        // Wire output unchanged from v0.2.0 — none of the new D.1 fields
        // appear, the read-tier shape is identical.
        let expected = #"_meta: {"matched_total":50,"returned":10,"filtered_by":["limit=10","scope=inbox"],"latency_ms":120,"redactions":[],"next_cursor":"page_2"}"#
        #expect(line == expected)
        // Assembler-side regex still matches.
        let regex = try Regex(#"^_meta: (\{.*\})$"#)
        #expect((try regex.wholeMatch(in: line)) != nil)
    }
}
