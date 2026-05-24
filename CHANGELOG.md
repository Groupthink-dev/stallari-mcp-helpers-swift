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

### Motivation
- Per DD-338 Phase E.swift (architect amendment 2026-05-23, substrate-corrected 2026-05-24) — greenfield Swift helper library shipped *before* the W5 Swift wave consumes it, so first-party Swift blade-mcps (`apple-mail-blade-mcp`, `apple-notes-blade-mcp`, and the Swift surface of `stallari-vault` served as `stallari-blade-mcp` via the daemon HTTP MCP per DD-242) can adopt the lib natively without a retrofit step.

### Notes
- Public API frozen during `0.x` series only against breaking changes within a minor; subject to refinement until `1.0.0`.
- The wire contract is specified by Stallari internal design record DD-338 (private; the public summary surfaces gradually as the contract stabilises).
- `1.0.0` cut once consumer blade-mcps have shipped against `0.x` for >30 days with no API churn.
