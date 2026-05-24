// Comprehensive coverage for `MetaEnvelope` + `formatMetaLine` +
// `appendMeta`. Test 11 (cross-language byte parity) is the load-bearing
// determinism + key-order + separator guard rolled into one — if it
// passes, the Swift `formatMetaLine` output is byte-equal to the Python +
// TypeScript sisters for the same input.

import Foundation
import Testing
@testable import MCPHelpers

@Suite("MetaEnvelope encoding")
struct MetaTests {

    // MARK: - Required-fields-only

    @Test("Required fields only — all 6 required keys present, redactions empty, next_cursor null")
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

    // MARK: - Cross-language byte parity (LOAD-BEARING)

    @Test("Cross-language byte parity with Python + TypeScript sisters")
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

    // MARK: - Regex contract

    @Test("formatMetaLine output matches the assembler-side regex contract")
    func regexContract() throws {
        let regex = try Regex(#"^_meta: (\{.*\})$"#)
        let combinations: [MetaEnvelope] = [
            MetaEnvelope(matchedTotal: 0, returned: 0, latencyMs: 0, filteredBy: []),
            MetaEnvelope(
                matchedTotal: 1,
                returned: 1,
                latencyMs: 1,
                filteredBy: ["a"],
                redactions: ["r"],
                nextCursor: "n"
            ),
            MetaEnvelope(
                matchedTotal: 99,
                returned: 50,
                latencyMs: 1000,
                filteredBy: [],
                errorNotes: ["e1", "e2"]
            ),
            MetaEnvelope(
                matchedTotal: 5,
                returned: 5,
                latencyMs: 5,
                filteredBy: ["x=1", "y=2"],
                redactions: ["pii"],
                nextCursor: "next",
                errorNotes: ["warn"]
            ),
        ]
        for meta in combinations {
            let line = try formatMetaLine(meta)
            let match = try regex.wholeMatch(in: line)
            #expect(match != nil, "Line failed regex contract: \(line)")
        }
    }

    // MARK: - Codable round-trip (decoding sanity)

    @Test("MetaEnvelope round-trips via Codable")
    func codableRoundTrip() throws {
        let original = MetaEnvelope(
            matchedTotal: 11,
            returned: 4,
            latencyMs: 88,
            filteredBy: ["c", "a", "b"],
            redactions: ["r1", "r2"],
            nextCursor: "abc",
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
        #expect(decoded.errorNotes == original.errorNotes)
    }
}
