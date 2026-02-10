import Foundation
import SwiftExecBytecode
import SwiftExecDiagnostics
import SwiftExecFrontend
import SwiftExecSecurity
import SwiftExecSemantic
import SwiftExecVM

public struct EngineRunRequest: Sendable {
    public let source: String
    public let fileName: String
    public let capabilities: CapabilitySet
    public let limits: ExecutionLimits

    public init(
        source: String,
        fileName: String = "UserCode.swift",
        capabilities: CapabilitySet = .default,
        limits: ExecutionLimits = .init()
    ) {
        self.source = source
        self.fileName = fileName
        self.capabilities = capabilities
        self.limits = limits
    }
}

public struct EngineRunResult: Sendable {
    public let value: RuntimeValue
    public let output: [String]
    public let diagnostics: [EngineDiagnostic]

    public init(value: RuntimeValue, output: [String], diagnostics: [EngineDiagnostic]) {
        self.value = value
        self.output = output
        self.diagnostics = diagnostics
    }
}

public struct EngineBuildPreviewRequest: Sendable {
    public let source: String
    public let fileName: String
    public let capabilities: CapabilitySet

    public init(
        source: String,
        fileName: String = "UserCode.swift",
        capabilities: CapabilitySet = .default
    ) {
        self.source = source
        self.fileName = fileName
        self.capabilities = capabilities
    }
}

public struct EngineBuildSymbolUsage: Sendable, Hashable {
    public let symbolID: SymbolID
    public let name: String
    public let requiredCapability: String?
    public let isAllowed: Bool

    public init(
        symbolID: SymbolID,
        name: String,
        requiredCapability: String?,
        isAllowed: Bool
    ) {
        self.symbolID = symbolID
        self.name = name
        self.requiredCapability = requiredCapability
        self.isAllowed = isAllowed
    }
}

public struct EngineBuildPreviewResult: Sendable {
    public let compilationDiagnostics: [EngineDiagnostic]
    public let usedSymbols: [EngineBuildSymbolUsage]
    public let blockedSymbols: [EngineBuildSymbolUsage]
    public let vmCompilationSucceeded: Bool
    public let bytecodeSize: Int
    public let instructionCount: Int
    public let constantCount: Int
    public let functionCount: Int

    public init(
        compilationDiagnostics: [EngineDiagnostic],
        usedSymbols: [EngineBuildSymbolUsage],
        blockedSymbols: [EngineBuildSymbolUsage],
        vmCompilationSucceeded: Bool,
        bytecodeSize: Int,
        instructionCount: Int,
        constantCount: Int,
        functionCount: Int
    ) {
        self.compilationDiagnostics = compilationDiagnostics
        self.usedSymbols = usedSymbols
        self.blockedSymbols = blockedSymbols
        self.vmCompilationSucceeded = vmCompilationSucceeded
        self.bytecodeSize = bytecodeSize
        self.instructionCount = instructionCount
        self.constantCount = constantCount
        self.functionCount = functionCount
    }
}

public final class Engine: @unchecked Sendable {
    public init() {}

    public func compile(_ request: EngineRunRequest) -> CompilationOutput {
        SwiftBytecodeCompiler.compile(source: request.source, fileName: request.fileName)
    }

    public func compileAndRun(_ request: EngineRunRequest) -> Result<EngineRunResult, RuntimeError> {
        let compilation = compile(request)
        guard let program = compilation.program else {
            let detail = compilation.diagnostics
                .map(DiagnosticFormatter.render)
                .joined(separator: "\n")
            if detail.isEmpty {
                return .failure(RuntimeError(message: "Compilation failed"))
            }
            return .failure(RuntimeError(message: "Compilation failed:\n\(detail)"))
        }
        do {
            let vm = VirtualMachine(
                program: program,
                configuration: .init(capabilities: request.capabilities, limits: request.limits)
            )
            let execution = try vm.run()
            return .success(
                .init(
                    value: execution.value,
                    output: execution.output,
                    diagnostics: compilation.diagnostics + execution.diagnostics
                )
            )
        } catch let error as RuntimeError {
            return .failure(error)
        } catch {
            return .failure(RuntimeError(message: String(describing: error)))
        }
    }

    public func buildPreview(_ request: EngineBuildPreviewRequest) -> EngineBuildPreviewResult {
        let compilation = compile(
            .init(
                source: request.source,
                fileName: request.fileName,
                capabilities: request.capabilities
            )
        )

        guard let program = compilation.program else {
            return .init(
                compilationDiagnostics: compilation.diagnostics,
                usedSymbols: [],
                blockedSymbols: [],
                vmCompilationSucceeded: false,
                bytecodeSize: 0,
                instructionCount: 0,
                constantCount: 0,
                functionCount: 0
            )
        }

        var symbolIDs = Set<SymbolID>()
        for instruction in program.instructions {
            if instruction.opcode == .callBridge || instruction.opcode == .callInit,
               let rawID = instruction.operands.first {
                symbolIDs.insert(SymbolID(truncatingIfNeeded: rawID))
            }
        }

        let usedSymbols = symbolIDs
            .sorted()
            .map { symbolID in
                let entry = BridgeSymbolCatalog.byID[symbolID]
                let isAllowed = SymbolPolicy.isAllowed(symbolID: symbolID, capabilities: request.capabilities)
                return EngineBuildSymbolUsage(
                    symbolID: symbolID,
                    name: entry?.name ?? "unknown(\(symbolID))",
                    requiredCapability: entry?.capability,
                    isAllowed: isAllowed
                )
            }
        let blockedSymbols = usedSymbols.filter { !$0.isAllowed }

        return .init(
            compilationDiagnostics: compilation.diagnostics,
            usedSymbols: usedSymbols,
            blockedSymbols: blockedSymbols,
            vmCompilationSucceeded: true,
            bytecodeSize: program.code.count,
            instructionCount: program.instructions.count,
            constantCount: program.constants.count,
            functionCount: program.functions.count
        )
    }
}
