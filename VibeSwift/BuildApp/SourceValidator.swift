import Foundation
import SwiftExecDiagnostics
import SwiftExecHost

struct SourceValidationReport: Sendable {
    let diagnostics: [String]
    let warnings: [String]
    let buildPreview: EngineBuildPreviewResult

    var hasErrors: Bool {
        !diagnostics.isEmpty
    }
}

struct SourceValidator {
    private let maxSourceBytes = 100_000
    private let allowedImports: Set<String> = ["Swift", "Foundation", "SwiftUI"]

    func validate(
        request: BuildAppRequest,
        engine: Engine
    ) -> SourceValidationReport {
        var diagnostics: [String] = []
        var warnings: [String] = []

        let sourceBytes = request.source.lengthOfBytes(using: .utf8)
        if sourceBytes > maxSourceBytes {
            diagnostics.append("Source exceeds max size of \(maxSourceBytes) bytes (\(sourceBytes) bytes).")
        }
        if request.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append("Source is empty.")
        }
        if request.source.contains("@_") {
            diagnostics.append("Unsupported private compiler attributes detected (\"@_\").")
        }

        diagnostics.append(contentsOf: invalidImportDiagnostics(in: request.source))
        diagnostics.append(contentsOf: appIdentityDiagnostics(appName: request.appName, bundleID: request.bundleIdentifier))

        let preview = engine.buildPreview(
            .init(
                source: request.source,
                capabilities: request.capabilities
            )
        )

        if preview.compilationDiagnostics.contains(where: { $0.severity == .error }) {
            // Native export mode can still proceed with syntax-valid source; we surface VM diagnostics as warnings.
            warnings.append("VM subset compilation reported errors. Native export can continue, but interpreted run may fail.")
        }
        warnings.append(contentsOf: preview.compilationDiagnostics.map { "[\($0.severity.rawValue.uppercased())] \($0.message)" })

        if !preview.blockedSymbols.isEmpty {
            let blockedNames = preview.blockedSymbols.map(\.name).joined(separator: ", ")
            diagnostics.append("Blocked symbols for selected capabilities: \(blockedNames)")
        }

        return SourceValidationReport(
            diagnostics: diagnostics,
            warnings: warnings,
            buildPreview: preview
        )
    }

    private func invalidImportDiagnostics(in source: String) -> [String] {
        var result: [String] = []
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("import ") else {
                continue
            }
            let module = line.replacingOccurrences(of: "import ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !allowedImports.contains(module) {
                result.append("Import \(module) is not allowed in Build App mode.")
            }
        }
        return result
    }

    private func appIdentityDiagnostics(appName: String, bundleID: String) -> [String] {
        var result: [String] = []
        if sanitizedIdentifier(appName).isEmpty {
            result.append("App name must include at least one letter or number.")
        }
        let bundlePattern = #"^[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+$"#
        if bundleID.range(of: bundlePattern, options: .regularExpression) == nil {
            result.append("Bundle identifier must look like com.example.AppName.")
        }
        return result
    }

    private func sanitizedIdentifier(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
