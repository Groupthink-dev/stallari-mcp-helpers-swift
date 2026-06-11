// Tests for the canonical HTTP transport policy (AUD-04-08 refusal
// matrix + AUD-04-31 bearer validation). Mirrors the Python + TS v0.4.0
// transport-module test suites.

import Foundation
import Testing
@testable import MCPHelpers

private let prefix = "TESTBLADE"
private let tokenVar = "TESTBLADE_MCP_TOKEN"

private func env(_ pairs: [String: String]) -> [String: String] { pairs }

@Suite("Transport — HTTP transport policy (AUD-04-08)")
struct TransportTests {

    // MARK: - Token refusal (refuse-to-serve, never warn-and-serve)

    @Test("Token absent → tokenMissing")
    func tokenAbsent() {
        #expect(throws: TransportPolicyError.tokenMissing(variable: tokenVar)) {
            _ = try resolveHTTPTransport(envPrefix: prefix, defaultPort: 9000, environment: env([:]))
        }
    }

    @Test("Token empty → tokenMissing")
    func tokenEmpty() {
        #expect(throws: TransportPolicyError.tokenMissing(variable: tokenVar)) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([tokenVar: ""])
            )
        }
    }

    @Test("Token whitespace-only → tokenMissing")
    func tokenWhitespaceOnly() {
        #expect(throws: TransportPolicyError.tokenMissing(variable: tokenVar)) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([tokenVar: " \t\n "])
            )
        }
    }

    @Test("Token surrounding whitespace is trimmed in the resolved config")
    func tokenTrimmed() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "  secret-tok  "])
        )
        #expect(config.token == "secret-tok")
    }

    // MARK: - Wildcard binds (unconditional refusal)

    @Test("Wildcard hosts throw even with token AND opt-in set", arguments: ["0.0.0.0", "::", "[::]", ""])
    func wildcardAlwaysRefused(host: String) {
        #expect(throws: TransportPolicyError.wildcardBind(host: host)) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([
                    tokenVar: "tok",
                    "TESTBLADE_MCP_HOST": host,
                    "TESTBLADE_MCP_ALLOW_NONLOOPBACK": "true",
                ])
            )
        }
    }

    // MARK: - Non-loopback opt-in

    @Test("Non-loopback host without opt-in → nonLoopbackWithoutOptIn")
    func nonLoopbackRefusedWithoutOptIn() {
        #expect(throws: TransportPolicyError.nonLoopbackWithoutOptIn(host: "192.168.1.10")) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([tokenVar: "tok", "TESTBLADE_MCP_HOST": "192.168.1.10"])
            )
        }
    }

    @Test("Non-loopback host with exact 'true' opt-in → passes")
    func nonLoopbackPassesWithExactTrue() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([
                tokenVar: "tok",
                "TESTBLADE_MCP_HOST": "192.168.1.10",
                "TESTBLADE_MCP_ALLOW_NONLOOPBACK": "true",
            ])
        )
        #expect(config.host == "192.168.1.10")
    }

    @Test("Non-loopback opt-in '1' / 'True' refused (strict exactness)", arguments: ["1", "True"])
    func nonLoopbackLooseOptInRefused(value: String) {
        #expect(throws: TransportPolicyError.nonLoopbackWithoutOptIn(host: "192.168.1.10")) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([
                    tokenVar: "tok",
                    "TESTBLADE_MCP_HOST": "192.168.1.10",
                    "TESTBLADE_MCP_ALLOW_NONLOOPBACK": value,
                ])
            )
        }
    }

    // MARK: - Loopback variants pass without any opt-in

    @Test("Loopback variants pass", arguments: ["127.0.0.1", "127.0.0.2", "::1", "localhost"])
    func loopbackVariantsPass(host: String) throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "tok", "TESTBLADE_MCP_HOST": host])
        )
        #expect(config.host == host)
    }

    @Test("Default host is 127.0.0.1")
    func defaultHostLoopback() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "tok"])
        )
        #expect(config.host == "127.0.0.1")
    }

    // MARK: - Port parsing

    @Test("Port unset → defaultPort")
    func portDefault() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9412,
            environment: env([tokenVar: "tok"])
        )
        #expect(config.port == 9412)
    }

    @Test("Port valid integer in range → used")
    func portValid() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "tok", "TESTBLADE_MCP_PORT": "8080"])
        )
        #expect(config.port == 8080)
    }

    @Test("Port strict parse + range refusals", arguments: ["abc", "", "0", "-1", "65536", "70000", "80.5"])
    func portInvalid(raw: String) {
        #expect(throws: TransportPolicyError.invalidPort(raw)) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([tokenVar: "tok", "TESTBLADE_MCP_PORT": raw])
            )
        }
    }

    @Test("Port boundary values 1 and 65535 pass")
    func portBoundaries() throws {
        let low = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "tok", "TESTBLADE_MCP_PORT": "1"])
        )
        #expect(low.port == 1)
        let high = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env([tokenVar: "tok", "TESTBLADE_MCP_PORT": "65535"])
        )
        #expect(high.port == 65535)
    }

    // MARK: - tokenVariable override

    @Test("tokenVariable override reads the custom variable")
    func tokenVariableOverride() throws {
        let config = try resolveHTTPTransport(
            envPrefix: prefix, defaultPort: 9000,
            environment: env(["CUSTOM_TOKEN_VAR": "custom-secret"]),
            tokenVariable: "CUSTOM_TOKEN_VAR"
        )
        #expect(config.token == "custom-secret")
    }

    @Test("tokenVariable override absent → tokenMissing names the override")
    func tokenVariableOverrideMissing() {
        #expect(throws: TransportPolicyError.tokenMissing(variable: "CUSTOM_TOKEN_VAR")) {
            _ = try resolveHTTPTransport(
                envPrefix: prefix, defaultPort: 9000,
                environment: env([tokenVar: "ignored-default-var"]),
                tokenVariable: "CUSTOM_TOKEN_VAR"
            )
        }
    }

    // MARK: - Error descriptions never contain token material

    @Test("tokenMissing description names the variable, not any token bytes")
    func errorDescriptionSafe() {
        let description = TransportPolicyError.tokenMissing(variable: tokenVar).description
        #expect(description.contains(tokenVar))
        #expect(description.contains("AUD-04-08"))
    }

    // MARK: - strictEnvBool

    @Test("strictEnvBool true ONLY for exact 'true'")
    func strictEnvBoolExactness() {
        #expect(strictEnvBool("true") == true)
        #expect(strictEnvBool("True") == false)
        #expect(strictEnvBool("TRUE") == false)
        #expect(strictEnvBool("1") == false)
        #expect(strictEnvBool("yes") == false)
        #expect(strictEnvBool(" true") == false)
        #expect(strictEnvBool("true ") == false)
        #expect(strictEnvBool("") == false)
        #expect(strictEnvBool(nil) == false)
    }
}

@Suite("Transport — bearer validation (AUD-04-31)")
struct BearerValidationTests {

    @Test("Valid Bearer header → true")
    func validBearer() {
        #expect(validateBearer(authorizationHeader: "Bearer tok-123", expectedToken: "tok-123"))
    }

    @Test("Scheme is case-insensitive", arguments: ["bearer tok-123", "BEARER tok-123", "BeArEr tok-123"])
    func caseInsensitiveScheme(header: String) {
        #expect(validateBearer(authorizationHeader: header, expectedToken: "tok-123"))
    }

    @Test("Wrong credential → false")
    func wrongCredential() {
        #expect(!validateBearer(authorizationHeader: "Bearer wrong", expectedToken: "tok-123"))
    }

    @Test("Missing header → false")
    func missingHeader() {
        #expect(!validateBearer(authorizationHeader: nil, expectedToken: "tok-123"))
    }

    @Test("Basic scheme → false even with matching credential")
    func basicSchemeRefused() {
        #expect(!validateBearer(authorizationHeader: "Basic tok-123", expectedToken: "tok-123"))
    }

    @Test("Bare credential without scheme → false")
    func bareCredentialRefused() {
        #expect(!validateBearer(authorizationHeader: "tok-123", expectedToken: "tok-123"))
    }

    @Test("Empty credential after scheme → false")
    func emptyCredentialRefused() {
        #expect(!validateBearer(authorizationHeader: "Bearer ", expectedToken: "tok-123"))
        #expect(!validateBearer(authorizationHeader: "Bearer", expectedToken: "tok-123"))
    }

    @Test("Length-mismatched credential → false (length-safe compare)")
    func lengthMismatch() {
        #expect(!validateBearer(authorizationHeader: "Bearer tok", expectedToken: "tok-123"))
        #expect(!validateBearer(authorizationHeader: "Bearer tok-123-extra", expectedToken: "tok-123"))
    }
}
