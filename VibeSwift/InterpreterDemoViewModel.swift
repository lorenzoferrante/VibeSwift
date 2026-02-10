import Foundation
import Combine
import SwiftUI
import SwiftExecDiagnostics
import SwiftExecHost
import SwiftExecSecurity
import SwiftExecSemantic

@MainActor
final class InterpreterDemoViewModel: ObservableObject {
    @Published var outputLines: [String] = []
    @Published var diagnosticLines: [String] = []
    @Published var resultText: String = ""
    @Published var isRunning: Bool = false

    @Published var isBuilding: Bool = false
    @Published var buildSummary: String = ""
    @Published var buildDiagnostics: [String] = []
    @Published var buildWarnings: [String] = []
    @Published var buildPackageURL: URL?
    @Published var buildManifestText: String = ""
    @Published var buildAppName: String = "GeneratedApp"
    @Published var buildBundleIdentifier: String = "com.example.GeneratedApp"

    @Published var allowSwiftUIBridge: Bool = false
    @Published var renderedView: AnyView?

    private let engine = Engine()
    private let buildService = BuildAppService()

    func run(source: String) {
        isRunning = true
        outputLines = []
        diagnosticLines = []
        resultText = ""
        renderedView = nil

        let capabilities: CapabilitySet = allowSwiftUIBridge
            ? [.foundationBasic, .diagnostics, .swiftUIBasic]
            : [.foundationBasic, .diagnostics]

        let request = EngineRunRequest(
            source: source,
            capabilities: capabilities,
            limits: .init(
                instructionBudget: 150_000,
                maxCallDepth: 128,
                maxValueStackDepth: 2_048,
                wallClockLimit: .seconds(1)
            )
        )

        switch engine.compileAndRun(request) {
        case let .success(result):
            outputLines = result.output
            resultText = result.value.description
            diagnosticLines = result.diagnostics.map(DiagnosticFormatter.render)
            if case let .native(box) = result.value, let anyView = box.value as? AnyView {
                renderedView = anyView
            } else {
                renderedView = nil
            }
        case let .failure(error):
            diagnosticLines = [DiagnosticFormatter.render(error)]
        }

        isRunning = false
    }

    func build(source: String) {
        isBuilding = true
        buildSummary = ""
        buildDiagnostics = []
        buildWarnings = []
        buildPackageURL = nil
        buildManifestText = ""

        let capabilities: CapabilitySet = allowSwiftUIBridge
            ? [.foundationBasic, .diagnostics, .swiftUIBasic]
            : [.foundationBasic, .diagnostics]

        let request = BuildAppRequest(
            source: source,
            appName: buildAppName,
            bundleIdentifier: buildBundleIdentifier,
            capabilities: capabilities,
            includeSwiftUI: allowSwiftUIBridge
        )

        do {
            let result = try buildService.build(request: request)
            buildSummary = result.summary
            buildDiagnostics = result.diagnostics
            buildWarnings = result.warnings
            buildPackageURL = result.packageURL
            buildManifestText = prettyPrintedManifest(result.manifest)
        } catch let error as BuildAppError {
            buildDiagnostics = [error.localizedDescription]
        } catch {
            buildDiagnostics = [error.localizedDescription]
        }

        isBuilding = false
    }

    deinit {
        buildService.cleanup()
    }

    private func prettyPrintedManifest(_ manifest: VibeAppManifest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(manifest),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
