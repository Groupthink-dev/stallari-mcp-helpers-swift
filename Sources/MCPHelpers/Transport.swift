// Canonical HTTP transport policy for Stallari-conformant Swift MCP
// servers — sister to the Python (`stallari_mcp_helpers.transport`) and
// TypeScript transport modules shipped in the v0.4.0 cross-language
// contract.
//
// AUD-04-08: Swift blades must stop hand-rolling bearer/bind policy.
// The locked policy is REFUSE-TO-SERVE, never warn-and-serve:
//
//   - Token-absent HTTP must REFUSE to serve. An unset / empty /
//     whitespace-only `{PREFIX}_MCP_TOKEN` throws — the server must never
//     come up unauthenticated, and never "warn and serve" either.
//   - Wildcard binds (`0.0.0.0`, `::`, `[::]`, empty host) are NEVER
//     permitted — unconditionally, regardless of token presence or any
//     opt-in flag.
//   - Non-loopback binds require the explicit opt-in
//     `{PREFIX}_MCP_ALLOW_NONLOOPBACK` set to EXACTLY `"true"`
//     (`strictEnvBool` — "1", "True", "TRUE", "yes" all refuse).
//   - Bearer validation is constant-time (SHA-256 digest comparison —
//     length-safe) and must be enforced on EVERY authenticated surface,
//     including WebSocket upgrade requests (AUD-04-31).
//
// Error descriptions are operator-actionable and never contain token
// material.
//
// Foundation-only (+ CryptoKit for the constant-time bearer compare).

import CryptoKit
import Foundation

// MARK: - Errors

/// Refusal reasons for `resolveHTTPTransport`. Descriptions are
/// operator-actionable; none ever includes token material.
public enum TransportPolicyError: Error, Equatable, CustomStringConvertible {
    /// `{PREFIX}_MCP_TOKEN` (or the overridden token variable) is unset,
    /// empty, or whitespace-only. HTTP must refuse to serve (AUD-04-08).
    case tokenMissing(variable: String)
    /// The bind host is a wildcard (`0.0.0.0`, `::`, `[::]`, or empty).
    /// Never permitted, regardless of token or opt-in.
    case wildcardBind(host: String)
    /// The bind host is not loopback and the non-loopback opt-in is not
    /// set to exactly `"true"`.
    case nonLoopbackWithoutOptIn(host: String)
    /// `{PREFIX}_MCP_PORT` is set but is not an integer in 1...65535.
    case invalidPort(String)

    public var description: String {
        switch self {
        case .tokenMissing(let variable):
            return (
                "HTTP transport refused: \(variable) is unset, empty, or "
                + "whitespace-only. Set \(variable) to a non-empty bearer "
                + "token before enabling HTTP — serving unauthenticated is "
                + "never permitted (AUD-04-08)."
            )
        case .wildcardBind(let host):
            return (
                "HTTP transport refused: bind host \"\(host)\" is a wildcard. "
                + "Wildcard binds are never permitted. Bind 127.0.0.1 (the "
                + "default), or set an explicit interface address together "
                + "with the non-loopback opt-in."
            )
        case .nonLoopbackWithoutOptIn(let host):
            return (
                "HTTP transport refused: bind host \"\(host)\" is not a "
                + "loopback address and the non-loopback opt-in is absent. "
                + "Set {PREFIX}_MCP_ALLOW_NONLOOPBACK=true (exactly "
                + "\"true\") to acknowledge exposing this server beyond "
                + "localhost, or bind a loopback address."
            )
        case .invalidPort(let raw):
            return (
                "HTTP transport refused: port value \"\(raw)\" is not an "
                + "integer in 1...65535. Fix or unset {PREFIX}_MCP_PORT "
                + "(the blade's default port is used when unset)."
            )
        }
    }
}

// MARK: - Resolved configuration

/// A policy-validated HTTP transport configuration. Construction goes
/// through `resolveHTTPTransport` — if you hold one of these, the bind
/// host and token have already passed the refusal matrix.
public struct HTTPTransportConfig: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let token: String

    public init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
    }
}

// MARK: - Strict env-bool

/// Strict environment boolean: `true` ONLY for the exact string `"true"`.
/// `"1"`, `"True"`, `"TRUE"`, `"yes"`, `nil`, and everything else are
/// `false`. Security opt-ins must be deliberate, not coincidental.
public func strictEnvBool(_ value: String?) -> Bool {
    return value == "true"
}

// MARK: - Transport resolution

/// Resolve and policy-check the HTTP transport configuration for a blade
/// from its environment (AUD-04-08 refusal matrix).
///
/// Environment variables read (with `envPrefix` substituted):
///   - `{PREFIX}_MCP_TOKEN` — required, non-empty after whitespace trim
///     (overridable via `tokenVariable`). Absent/blank → throws
///     ``TransportPolicyError/tokenMissing(variable:)`` — the server must
///     REFUSE to serve, never warn-and-serve unauthenticated.
///   - `{PREFIX}_MCP_HOST` — bind host, default `"127.0.0.1"`. Wildcards
///     (`"0.0.0.0"`, `"::"`, `"[::]"`, `""`) throw unconditionally; a
///     non-loopback host throws unless `{PREFIX}_MCP_ALLOW_NONLOOPBACK`
///     is exactly `"true"`. Loopback = `"localhost"`, any 127.0.0.0/8
///     dotted-quad, or `"::1"`.
///   - `{PREFIX}_MCP_PORT` — optional; when set must parse as an Int in
///     1...65535 or ``TransportPolicyError/invalidPort(_:)`` is thrown.
///     `defaultPort` is used when unset.
///   - `{PREFIX}_MCP_ALLOW_NONLOOPBACK` — strict opt-in, see
///     ``strictEnvBool(_:)``.
///
/// - Parameters:
///   - envPrefix: blade env prefix, e.g. `"APPLE_NOTES"`.
///   - defaultPort: port used when `{PREFIX}_MCP_PORT` is unset.
///   - environment: injection point for tests; defaults to
///     `ProcessInfo.processInfo.environment`.
///   - tokenVariable: full variable name overriding the default
///     `{PREFIX}_MCP_TOKEN`.
public func resolveHTTPTransport(
    envPrefix: String,
    defaultPort: Int,
    environment: [String: String]? = nil,
    tokenVariable: String? = nil
) throws -> HTTPTransportConfig {
    let env = environment ?? ProcessInfo.processInfo.environment

    // 1. Token — refuse-to-serve when unset/empty/whitespace-only.
    let tokenVar = tokenVariable ?? "\(envPrefix)_MCP_TOKEN"
    let token = (env[tokenVar] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
        throw TransportPolicyError.tokenMissing(variable: tokenVar)
    }

    // 2. Host — wildcard refusal is unconditional; non-loopback requires
    //    the strict opt-in.
    let host = env["\(envPrefix)_MCP_HOST"] ?? "127.0.0.1"
    let wildcardHosts: Set<String> = ["0.0.0.0", "::", "[::]", ""]
    if wildcardHosts.contains(host) {
        throw TransportPolicyError.wildcardBind(host: host)
    }
    if !isLoopbackHost(host) {
        guard strictEnvBool(env["\(envPrefix)_MCP_ALLOW_NONLOOPBACK"]) else {
            throw TransportPolicyError.nonLoopbackWithoutOptIn(host: host)
        }
    }

    // 3. Port — strict parse + range when set; default otherwise.
    var port = defaultPort
    if let rawPort = env["\(envPrefix)_MCP_PORT"] {
        guard let parsed = Int(rawPort), (1...65535).contains(parsed) else {
            throw TransportPolicyError.invalidPort(rawPort)
        }
        port = parsed
    }

    return HTTPTransportConfig(host: host, port: port, token: token)
}

/// Loopback = `"localhost"`, `"::1"`, or a dotted-quad that parses with
/// first octet 127 (127.0.0.0/8).
private func isLoopbackHost(_ host: String) -> Bool {
    if host == "localhost" || host == "::1" { return true }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    var octets: [Int] = []
    octets.reserveCapacity(4)
    for part in parts {
        guard !part.isEmpty,
              part.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(part),
              (0...255).contains(value) else {
            return false
        }
        octets.append(value)
    }
    return octets[0] == 127
}

// MARK: - Bearer validation

/// Validate an `Authorization` header against the expected bearer token.
///
/// Parses `"Bearer <credential>"` with a case-insensitive scheme, then
/// compares the credential against `expectedToken` in constant time:
/// both sides are hashed with SHA-256 and the digests compared byte-wise
/// accumulating a difference flag — length-safe (digests are fixed-width)
/// and free of early-exit timing leaks.
///
/// Returns `false` for a missing header, a non-Bearer scheme, or an
/// empty credential.
///
/// IMPORTANT (AUD-04-31): callers MUST enforce this check on WebSocket
/// upgrade requests too, not just plain HTTP requests — the upgrade
/// handshake is an HTTP request and is just as unauthenticated without
/// it.
public func validateBearer(authorizationHeader: String?, expectedToken: String) -> Bool {
    guard let header = authorizationHeader else { return false }
    let trimmed = header.trimmingCharacters(in: .whitespaces)
    guard let separatorIndex = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
        // Bare credential with no scheme — refuse.
        return false
    }
    let scheme = trimmed[..<separatorIndex]
    guard scheme.lowercased() == "bearer" else { return false }
    let credential = trimmed[trimmed.index(after: separatorIndex)...]
        .trimmingCharacters(in: .whitespaces)
    guard !credential.isEmpty else { return false }

    let lhs = SHA256.hash(data: Data(credential.utf8))
    let rhs = SHA256.hash(data: Data(expectedToken.utf8))
    var difference: UInt8 = 0
    for (a, b) in zip(lhs, rhs) {
        difference |= a ^ b
    }
    return difference == 0
}
