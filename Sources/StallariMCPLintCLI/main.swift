// stallari-mcp-lint — CLI front-end for the S-AUD-001 audit-surface
// honesty linter (DD-338 Phase B Swift sibling).
//
// Usage:
//   stallari-mcp-lint <blade-source-root> --catalog <catalog.json>
//                     [--output <sidecar.json>] [--strict]
//
// Exit codes:
//   0  — verdict produced, no over/under-declared in strict mode
//   1  — strict mode + at least one over/under-declared verdict
//   2  — argument or catalog-load error
//
// Without `--strict`, exit is always 0 even when there are verdict
// failures (mirrors the Python sibling so CI integrations can choose
// whether the lint is informational or gating).

import Foundation
import MCPHelpers

// NOTE: top-level executable (file named main.swift) — do NOT add @main.
// Top-level code is the entrypoint.

enum StallariMCPLintCLI {
    static func run(arguments: [String]) -> Int {
        var sourceRoot: String? = nil
        var catalogPath: String? = nil
        var outputPath: String? = nil
        var strict = false

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "-h", "--help":
                printUsage()
                return 0
            case "--catalog":
                i += 1
                guard i < arguments.count else {
                    FileHandle.standardError.write(Data("error: --catalog requires a value\n".utf8))
                    return 2
                }
                catalogPath = arguments[i]
            case "--output":
                i += 1
                guard i < arguments.count else {
                    FileHandle.standardError.write(Data("error: --output requires a value\n".utf8))
                    return 2
                }
                outputPath = arguments[i]
            case "--strict":
                strict = true
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write(Data("error: unknown flag \(arg)\n".utf8))
                    return 2
                }
                if sourceRoot != nil {
                    FileHandle.standardError.write(Data("error: more than one source-root argument\n".utf8))
                    return 2
                }
                sourceRoot = arg
            }
            i += 1
        }

        guard let sourceRoot else {
            FileHandle.standardError.write(Data("error: source-root argument is required\n".utf8))
            printUsage()
            return 2
        }
        guard let catalogPath else {
            FileHandle.standardError.write(Data("error: --catalog is required\n".utf8))
            printUsage()
            return 2
        }

        // Load + parse catalog.
        let catalogURL = URL(fileURLWithPath: catalogPath)
        let catalogEntry: [String: Any]
        do {
            let data = try Data(contentsOf: catalogURL)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                FileHandle.standardError.write(Data("error: catalog \(catalogPath) is not a JSON object\n".utf8))
                return 2
            }
            catalogEntry = parsed
        } catch {
            let msg = "error: failed to load catalog \(catalogPath): \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            return 2
        }

        let rootURL = URL(fileURLWithPath: sourceRoot)
        let result = lintBlade(bladeSourceRoot: rootURL, catalogEntry: catalogEntry)
        let payload: String
        do {
            payload = try result.canonicalJSON()
        } catch {
            FileHandle.standardError.write(Data("error: failed to render verdict JSON: \(error)\n".utf8))
            return 2
        }

        if let outputPath {
            do {
                try (payload + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                let msg = "error: failed to write sidecar \(outputPath): \(error)\n"
                FileHandle.standardError.write(Data(msg.utf8))
                return 2
            }
        } else {
            print(payload)
        }

        if strict {
            let s = result.summary
            if s.overDeclaredCount > 0 || s.underDeclaredCount > 0 {
                return 1
            }
        }
        return 0
    }

    static func printUsage() {
        let text = """
        usage: stallari-mcp-lint <blade-source-root> --catalog <catalog.json>
                                 [--output <sidecar.json>] [--strict]

        Static audit-surface honesty linter for Stallari Swift blade-mcps
        (S-AUD-001 / DD-338 Phase B Swift).

        Arguments:
          <blade-source-root>   Path to the blade's Swift source root (repo
                                or Sources directory).

        Options:
          --catalog PATH        Path to the blade's catalog JSON entry.
          --output PATH         Write verdict JSON to PATH instead of stdout.
          --strict              Exit non-zero (1) on any over-declared /
                                under-declared verdict. Indeterminate
                                verdicts do NOT trip strict mode.
          -h, --help            Show this help and exit.

        """
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

exit(Int32(StallariMCPLintCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))))
