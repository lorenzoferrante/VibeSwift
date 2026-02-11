import Foundation
import SwiftExecBridgeRuntime
import SwiftExecDiagnostics
import SwiftExecHost
import SwiftExecSecurity
import SwiftExecSemantic

@MainActor
final class LiveScriptRuntime {
    enum RenderReason: String {
        case initial
        case sourceChanged
        case stateMutation
        case action
    }

    private enum Invocation {
        case render(RenderReason)
        case action(functionName: String)
    }

    private let engine = Engine()
    private let capabilities: CapabilitySet
    private var source: String
    private var isExecuting = false

    let store: RuntimeStore

    private(set) var outputLines: [String] = []
    private(set) var diagnosticLines: [String] = []
    private(set) var resultText: String = ""
    private(set) var lastRuntimeError: String?

    init(
        source: String,
        capabilities: CapabilitySet,
        initialState: [String: IRValue]
    ) {
        self.source = source
        self.capabilities = capabilities
        self.store = RuntimeStore(state: initialState, ir: .placeholder)
        self.store.onStateMutation = { [weak self] path in
            self?.handleStateMutation(path: path)
        }
    }

    func start() {
        run(.render(.initial))
    }

    func updateSource(_ source: String, recompute: Bool = true) {
        self.source = source
        guard recompute else {
            return
        }
        run(.render(.sourceChanged))
    }

    func dispatch(actionID: String) {
        guard let functionName = sanitizeFunctionName(actionID) else {
            lastRuntimeError = "Invalid action id: \(actionID)"
            diagnosticLines = [lastRuntimeError ?? "Invalid action id"]
            return
        }
        run(.action(functionName: functionName))
    }

    func stateSnapshotText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store.state),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    func irSnapshotText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store.ir),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func handleStateMutation(path: String) {
        guard !isExecuting else {
            return
        }
        guard !path.isEmpty else {
            return
        }
        run(.render(.stateMutation))
    }

    private func run(_ invocation: Invocation) {
        guard !isExecuting else {
            return
        }

        isExecuting = true
        defer { isExecuting = false }

        let request = EngineRunRequest(
            source: invocationSource(for: invocation),
            capabilities: capabilities,
            limits: .init(
                instructionBudget: 200_000,
                maxCallDepth: 128,
                maxValueStackDepth: 4_096,
                wallClockLimit: .seconds(1)
            )
        )

        let context = BridgeScriptContext(
            stateGet: { [weak store] path in
                guard let store, let value = store.value(at: path) else {
                    return .none
                }
                return value.runtimeValue
            },
            stateSet: { [weak store] path, value in
                guard let store else {
                    return
                }
                let mapped = IRValue.fromRuntimeValue(value) ?? .null
                store.setValue(mapped, at: path, triggerRecompute: false)
            },
            stateBind: { path in
                .dictionary(["$binding": .string(path)])
            }
        )

        let result = BridgeRuntime.withScriptContext(context) {
            engine.compileAndRun(request)
        }

        switch result {
        case let .success(success):
            outputLines = success.output
            resultText = success.value.description
            diagnosticLines = success.diagnostics.map(DiagnosticFormatter.render)
            lastRuntimeError = nil

            if let tree = ViewTree.fromRuntimeValue(
                success.value,
                defaultCapabilities: capabilityNames(),
                defaultIRVersion: 1
            ) {
                store.ir = tree
            } else {
                lastRuntimeError = "body() must return a ViewTree node."
                diagnosticLines.append(lastRuntimeError ?? "Invalid body() output")
            }

        case let .failure(error):
            outputLines = []
            resultText = ""
            diagnosticLines = [DiagnosticFormatter.render(error)]
            lastRuntimeError = error.message
        }
    }

    private func invocationSource(for invocation: Invocation) -> String {
        var content = source
        if !content.hasSuffix("\n") {
            content.append("\n")
        }
        switch invocation {
        case .render:
            content.append("return body()\n")
        case let .action(functionName):
            content.append("\(functionName)()\n")
            content.append("return body()\n")
        }
        return content
    }

    private func sanitizeFunctionName(_ value: String) -> String? {
        guard let first = value.first else {
            return nil
        }
        let validStart = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let validBody = validStart.union(.decimalDigits)
        guard String(first).rangeOfCharacter(from: validStart) != nil else {
            return nil
        }
        for char in value.dropFirst() {
            guard String(char).rangeOfCharacter(from: validBody) != nil else {
                return nil
            }
        }
        return value
    }

    private func capabilityNames() -> [String] {
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

private extension ViewTree {
    static var placeholder: ViewTree {
        ViewTree(
            irVersion: 1,
            capabilities: [],
            root: ViewNode(
                id: "root-placeholder",
                type: "VStack",
                props: [:],
                children: [],
                modifiers: [],
                events: []
            )
        )
    }
}
