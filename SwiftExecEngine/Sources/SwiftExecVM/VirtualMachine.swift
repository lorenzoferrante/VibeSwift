import Foundation
import SwiftExecBridgeRuntime
import SwiftExecBytecode
import SwiftExecDiagnostics
import SwiftExecSecurity
import SwiftExecSemantic

public struct VMConfiguration: Sendable {
    public var capabilities: CapabilitySet
    public var limits: ExecutionLimits

    public init(capabilities: CapabilitySet = .default, limits: ExecutionLimits = .init()) {
        self.capabilities = capabilities
        self.limits = limits
    }
}

public struct CallFrame: Sendable {
    public let functionID: FunctionID
    public let functionName: String
    public let returnInstructionIndex: Int?
    public let callSiteInstructionIndex: Int?
    public var locals: [RuntimeValue]

    public init(
        functionID: FunctionID,
        functionName: String,
        returnInstructionIndex: Int?,
        callSiteInstructionIndex: Int?,
        locals: [RuntimeValue]
    ) {
        self.functionID = functionID
        self.functionName = functionName
        self.returnInstructionIndex = returnInstructionIndex
        self.callSiteInstructionIndex = callSiteInstructionIndex
        self.locals = locals
    }
}

public final class VirtualMachine: @unchecked Sendable {
    private let program: BytecodeProgram
    private let configuration: VMConfiguration
    private var resourceGuard: ResourceGuard

    private var instructionPointer: Int = 0
    private var valueStack: [RuntimeValue] = []
    private var callStack: [CallFrame] = []
    private var outputBuffer: [String] = []
    private var inlineCaches = VMInlineCaches()

    public init(program: BytecodeProgram, configuration: VMConfiguration = .init()) {
        self.program = program
        self.configuration = configuration
        self.resourceGuard = ResourceGuard(limits: configuration.limits)
    }

    public func run() throws -> VMExecutionResult {
        let entry = program.functions.first(where: \.isEntryPoint) ?? program.functions.first
        guard let entry else {
            throw RuntimeError(message: "Program has no entry function")
        }

        callStack = [
            CallFrame(
                functionID: entry.id,
                functionName: entry.name,
                returnInstructionIndex: nil,
                callSiteInstructionIndex: nil,
                locals: .init(repeating: .none, count: entry.localCount)
            )
        ]
        instructionPointer = entry.entryInstructionIndex

        do {
            while instructionPointer >= 0 && instructionPointer < program.instructions.count {
                try resourceGuard.onInstructionExecuted()
                let currentInstruction = instructionPointer
                let instruction = program.instructions[currentInstruction]
                instructionPointer += 1
                try execute(instruction, at: currentInstruction)
            }
        } catch {
            throw decorateError(error, failingInstructionIndex: max(0, instructionPointer - 1))
        }

        let value = valueStack.last ?? .none
        return VMExecutionResult(value: value, diagnostics: [], output: outputBuffer)
    }

    private func execute(_ instruction: DecodedInstruction, at index: Int) throws {
        switch instruction.opcode {
        case .nop:
            return
        case .halt:
            instructionPointer = program.instructions.count

        case .pushConst:
            let constantIndex = try requireOperand(instruction, at: 0)
            let value = try runtimeValue(constantIndex: constantIndex)
            try push(value)

        case .pop:
            _ = pop()

        case .dup:
            let value = try requireTop()
            try push(value)

        case .loadLocal:
            let localIndex = try requireOperand(instruction, at: 0)
            let value = try loadLocal(at: localIndex)
            try push(value)

        case .storeLocal:
            let localIndex = try requireOperand(instruction, at: 0)
            let value = try popRequired()
            try storeLocal(value, at: localIndex)

        case .jump:
            let target = try requireOperand(instruction, at: 0)
            instructionPointer = target

        case .jumpIfFalse:
            let target = try requireOperand(instruction, at: 0)
            let condition = try popRequired()
            if !condition.truthyValue {
                instructionPointer = target
            }

        case .jumpIfTrue:
            let target = try requireOperand(instruction, at: 0)
            let condition = try popRequired()
            if condition.truthyValue {
                instructionPointer = target
            }

        case .returnValue:
            let returnedValue = pop() ?? .none
            guard let frame = callStack.popLast() else {
                throw RuntimeError(message: "return with empty call stack")
            }
            if let resumeAt = frame.returnInstructionIndex {
                instructionPointer = resumeAt
                try push(returnedValue)
            } else {
                valueStack = [returnedValue]
                instructionPointer = program.instructions.count
            }

        case .callUser:
            let functionRaw = try requireOperand(instruction, at: 0)
            let argCount = try requireOperand(instruction, at: 1)
            try callUser(functionID: FunctionID(functionRaw), argCount: argCount, callSite: index)

        case .callBridge, .callInit:
            let symbolRaw = try requireOperand(instruction, at: 0)
            let argCount = try requireOperand(instruction, at: 1)
            let hasReceiver = (try? requireOperand(instruction, at: 2)) == 1
            let args = try popArguments(argCount)
            let receiver = hasReceiver ? try popRequired() : nil
            let context = BridgeInvocationContext(capabilities: configuration.capabilities)
            let symbolID = SymbolID(symbolRaw)
            let receiverType = receiver.map(runtimeTypeName) ?? "none"
            inlineCaches.bridge[.init(instructionIndex: index, receiverType: receiverType)] = .init(symbolID: symbolID)
            let value = try BridgeRuntime.invoke(
                symbolID: symbolID,
                receiver: receiver,
                args: args,
                context: context,
                printSink: { [weak self] message in
                    self?.outputBuffer.append(message)
                }
            )
            try push(value)

        case .makeStruct:
            let typeRaw = try requireOperand(instruction, at: 0)
            let fieldCount = try requireOperand(instruction, at: 1)
            guard instruction.operands.count >= (2 + fieldCount) else {
                throw RuntimeError(message: "makeStruct missing field operands")
            }
            let values = try popArguments(fieldCount)
            var fields: [FieldID: RuntimeValue] = [:]
            for idx in 0..<fieldCount {
                let fieldID = FieldID(instruction.operands[idx + 2])
                fields[fieldID] = values[idx]
                inlineCaches.fields.insert(.init(instructionIndex: index, typeID: TypeID(typeRaw), fieldID: fieldID))
            }
            try push(.customInstance(.init(typeID: TypeID(typeRaw), fields: fields)))

        case .getField:
            let fieldRaw = try requireOperand(instruction, at: 0)
            let base = try popRequired()
            guard case let .customInstance(instance) = base else {
                throw RuntimeError(message: "getField expects custom instance")
            }
            guard let value = instance.fields[FieldID(fieldRaw)] else {
                throw RuntimeError(message: "field \(fieldRaw) missing on instance type \(instance.typeID)")
            }
            try push(value)

        case .setField:
            let fieldRaw = try requireOperand(instruction, at: 0)
            let value = try popRequired()
            let base = try popRequired()
            guard case let .customInstance(instance) = base else {
                throw RuntimeError(message: "setField expects custom instance")
            }
            var updated = instance
            updated.fields[FieldID(fieldRaw)] = value
            try push(.customInstance(updated))
        }
    }

    private func callUser(functionID: FunctionID, argCount: Int, callSite: Int) throws {
        guard let target = program.functions.first(where: { $0.id == functionID }) else {
            throw RuntimeError(message: "Unknown function ID: \(functionID)")
        }
        let args = try popArguments(argCount)
        var locals = Array(repeating: RuntimeValue.none, count: target.localCount)
        for (idx, arg) in args.enumerated() where idx < locals.count {
            locals[idx] = arg
        }
        let frame = CallFrame(
            functionID: target.id,
            functionName: target.name,
            returnInstructionIndex: instructionPointer,
            callSiteInstructionIndex: callSite,
            locals: locals
        )
        callStack.append(frame)
        try resourceGuard.ensureCallDepth(callStack.count)
        instructionPointer = target.entryInstructionIndex
    }

    private func runtimeValue(constantIndex: Int) throws -> RuntimeValue {
        guard program.constants.indices.contains(constantIndex) else {
            throw RuntimeError(message: "Constant index out of range: \(constantIndex)")
        }
        switch program.constants[constantIndex] {
        case .none:
            return .none
        case let .int64(value):
            return .int64(value)
        case let .double(value):
            return .double(value)
        case let .bool(value):
            return .bool(value)
        case let .string(value):
            return .string(value)
        case let .symbol(value):
            return .int64(Int64(value))
        case let .type(value):
            return .int64(Int64(value))
        case let .field(value):
            return .int64(Int64(value))
        case let .function(value):
            return .int64(Int64(value))
        }
    }

    private func loadLocal(at index: Int) throws -> RuntimeValue {
        guard !callStack.isEmpty else {
            throw RuntimeError(message: "loadLocal with empty call stack")
        }
        guard callStack[callStack.count - 1].locals.indices.contains(index) else {
            throw RuntimeError(message: "Invalid local index \(index)")
        }
        return callStack[callStack.count - 1].locals[index]
    }

    private func storeLocal(_ value: RuntimeValue, at index: Int) throws {
        guard !callStack.isEmpty else {
            throw RuntimeError(message: "storeLocal with empty call stack")
        }
        guard callStack[callStack.count - 1].locals.indices.contains(index) else {
            throw RuntimeError(message: "Invalid local index \(index)")
        }
        callStack[callStack.count - 1].locals[index] = value
    }

    private func push(_ value: RuntimeValue) throws {
        valueStack.append(value)
        try resourceGuard.ensureValueStackDepth(valueStack.count)
    }

    private func pop() -> RuntimeValue? {
        valueStack.popLast()
    }

    private func popRequired() throws -> RuntimeValue {
        guard let value = pop() else {
            throw RuntimeError(message: "Value stack underflow")
        }
        return value
    }

    private func requireTop() throws -> RuntimeValue {
        guard let value = valueStack.last else {
            throw RuntimeError(message: "Value stack is empty")
        }
        return value
    }

    private func requireOperand(_ instruction: DecodedInstruction, at index: Int) throws -> Int {
        guard instruction.operands.indices.contains(index) else {
            throw RuntimeError(message: "Missing operand \(index) for \(instruction.opcode)")
        }
        return Int(instruction.operands[index])
    }

    private func popArguments(_ count: Int) throws -> [RuntimeValue] {
        guard count >= 0 else {
            throw RuntimeError(message: "Invalid argument count \(count)")
        }
        var args: [RuntimeValue] = []
        args.reserveCapacity(count)
        for _ in 0..<count {
            args.append(try popRequired())
        }
        return args.reversed()
    }

    private func decorateError(_ error: Error, failingInstructionIndex: Int?) -> RuntimeError {
        let span = failingInstructionIndex.flatMap { program.spans[$0] }
        let stack = callStack.map { frame in
            let callSiteSpan = frame.callSiteInstructionIndex.flatMap { program.spans[$0] }
            return StackFrameDiagnostic(functionName: frame.functionName, span: callSiteSpan)
        }

        if let runtimeError = error as? RuntimeError {
            return RuntimeError(
                message: runtimeError.message,
                symbolID: runtimeError.symbolID,
                failingInstructionIndex: runtimeError.failingInstructionIndex ?? failingInstructionIndex,
                span: runtimeError.span ?? span,
                callStack: runtimeError.callStack.isEmpty ? stack : runtimeError.callStack
            )
        }
        return RuntimeError(
            message: String(describing: error),
            failingInstructionIndex: failingInstructionIndex,
            span: span,
            callStack: stack
        )
    }

    private func runtimeTypeName(_ value: RuntimeValue) -> String {
        switch value {
        case .none:
            return "none"
        case .int64:
            return "Int64"
        case .double:
            return "Double"
        case .bool:
            return "Bool"
        case .string:
            return "String"
        case .array:
            return "Array"
        case .dictionary:
            return "Dictionary"
        case .native:
            return "Native"
        case let .customInstance(instance):
            return "Custom(\(instance.typeID))"
        }
    }
}
