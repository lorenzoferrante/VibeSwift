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
    @Published var isLiveRunning: Bool = false
    @Published var liveStatusText: String = ""
    @Published var liveStateText: String = ""
    @Published var liveIRText: String = ""

    private let engine = Engine()
    private let buildService = BuildAppService()
    private var runPreviewStore: RuntimeStore?
    private var liveRuntime: LiveScriptRuntime?

    func run(source: String) {
        isRunning = true
        outputLines = []
        diagnosticLines = []
        resultText = ""
        renderedView = nil
        liveStatusText = ""
        liveStateText = ""
        liveIRText = ""
        liveRuntime = nil
        runPreviewStore = nil

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
            if let tree = ViewTree.fromRuntimeValue(
                result.value,
                defaultCapabilities: capabilityNames(capabilities),
                defaultIRVersion: 1
            ) {
                let previewStore = RuntimeStore(state: [:], ir: tree)
                runPreviewStore = previewStore
                renderedView = AnyView(
                    LiveRenderedTreeView(
                        store: previewStore,
                        dispatch: { _ in }
                    )
                )
            } else if case let .native(box) = result.value, let anyView = box.value as? AnyView {
                renderedView = anyView
            } else {
                renderedView = nil
            }
        case let .failure(error):
            diagnosticLines = [DiagnosticFormatter.render(error)]
        }

        isRunning = false
    }

    func runLive(source: String) {
        isLiveRunning = true
        outputLines = []
        diagnosticLines = []
        resultText = ""
        renderedView = nil

        let capabilities: CapabilitySet = allowSwiftUIBridge
            ? [.foundationBasic, .diagnostics, .swiftUIBasic]
            : [.foundationBasic, .diagnostics]

        let runtime = LiveScriptRuntime(
            source: source,
            capabilities: capabilities,
            initialState: defaultLiveState()
        )
        runtime.start()
        liveRuntime = runtime
        runPreviewStore = nil

        renderedView = AnyView(
            LiveRenderedTreeView(
                store: runtime.store,
                dispatch: { [weak self] actionID in
                    self?.dispatchLiveAction(actionID)
                }
            )
        )
        syncLiveOutput(from: runtime)
        isLiveRunning = false
    }

    func recomputeLive(source: String) {
        guard let runtime = liveRuntime else {
            runLive(source: source)
            return
        }
        runtime.updateSource(source, recompute: true)
        syncLiveOutput(from: runtime)
    }

    func dispatchLiveAction(_ actionID: String) {
        guard let runtime = liveRuntime else {
            return
        }
        runtime.dispatch(actionID: actionID)
        syncLiveOutput(from: runtime)
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

    private func syncLiveOutput(from runtime: LiveScriptRuntime) {
        outputLines = runtime.outputLines
        diagnosticLines = runtime.diagnosticLines
        resultText = runtime.resultText
        liveStateText = runtime.stateSnapshotText()
        liveIRText = runtime.irSnapshotText()
        if let error = runtime.lastRuntimeError {
            liveStatusText = "Live renderer error: \(error)"
        } else {
            liveStatusText = "Live renderer ready."
        }
    }

    private func defaultLiveState() -> [String: IRValue] {
        [
            "title": .string("Live ViewTree Renderer"),
            "name": .string("Vibe"),
            "enabled": .bool(true)
        ]
    }

    private func capabilityNames(_ capabilities: CapabilitySet) -> [String] {
        var names: [String] = []
        if capabilities.contains(.foundationBasic) {
            names.append("foundationBasic")
        }
        if capabilities.contains(.dateFormatting) {
            names.append("dateFormatting")
        }
        if capabilities.contains(.swiftUIBasic) {
            names.append("swiftUIBasic")
        }
        if capabilities.contains(.diagnostics) {
            names.append("diagnostics")
        }
        return names
    }
}
