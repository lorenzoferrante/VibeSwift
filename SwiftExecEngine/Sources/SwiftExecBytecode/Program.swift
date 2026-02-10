import Foundation
import SwiftExecDiagnostics
import SwiftExecSemantic

public struct DecodedInstruction: Sendable {
    public let opcode: Opcode
    public let operands: [Int64]

    public init(opcode: Opcode, operands: [Int64]) {
        self.opcode = opcode
        self.operands = operands
    }
}

public struct InstructionDescriptor: Sendable {
    public let opcode: Opcode
    public var operands: [Int64]
    public let span: SourceSpan?

    public init(opcode: Opcode, operands: [Int64] = [], span: SourceSpan? = nil) {
        self.opcode = opcode
        self.operands = operands
        self.span = span
    }
}

public struct FunctionMeta: Sendable {
    public let id: FunctionID
    public let name: String
    public let entryInstructionIndex: Int
    public let arity: Int
    public let localCount: Int
    public let isEntryPoint: Bool

    public init(
        id: FunctionID,
        name: String,
        entryInstructionIndex: Int,
        arity: Int,
        localCount: Int,
        isEntryPoint: Bool = false
    ) {
        self.id = id
        self.name = name
        self.entryInstructionIndex = entryInstructionIndex
        self.arity = arity
        self.localCount = localCount
        self.isEntryPoint = isEntryPoint
    }
}

public struct BytecodeProgram: Sendable {
    public let code: [UInt8]
    public let constants: [Constant]
    public let functions: [FunctionMeta]
    public let symbols: ProgramSymbols
    public let instructions: [DecodedInstruction]
    public let spans: [Int: SourceSpan]

    public init(
        code: [UInt8],
        constants: [Constant],
        functions: [FunctionMeta],
        symbols: ProgramSymbols,
        instructions: [DecodedInstruction],
        spans: [Int: SourceSpan]
    ) {
        self.code = code
        self.constants = constants
        self.functions = functions
        self.symbols = symbols
        self.instructions = instructions
        self.spans = spans
    }
}

public enum BytecodeAssembler {
    public static func assemble(
        descriptors: [InstructionDescriptor],
        constants: [Constant],
        functions: [FunctionMeta],
        symbols: ProgramSymbols
    ) -> BytecodeProgram {
        var code: [UInt8] = []
        var spans: [Int: SourceSpan] = [:]
        var instructions: [DecodedInstruction] = []
        instructions.reserveCapacity(descriptors.count)

        for (instructionIndex, descriptor) in descriptors.enumerated() {
            code.append(descriptor.opcode.rawValue)
            VarintCodec.encodeUnsigned(UInt64(descriptor.operands.count), into: &code)
            for operand in descriptor.operands {
                VarintCodec.encodeSigned(operand, into: &code)
            }
            instructions.append(DecodedInstruction(opcode: descriptor.opcode, operands: descriptor.operands))
            if let span = descriptor.span {
                spans[instructionIndex] = span
            }
        }

        return BytecodeProgram(
            code: code,
            constants: constants,
            functions: functions,
            symbols: symbols,
            instructions: instructions,
            spans: spans
        )
    }

    public static func decodeInstructions(from code: [UInt8]) throws -> [DecodedInstruction] {
        var instructions: [DecodedInstruction] = []
        var offset = 0
        while offset < code.count {
            let opcodeRaw = code[offset]
            offset += 1
            guard let opcode = Opcode(rawValue: opcodeRaw) else {
                throw DecodeError.invalidOpcode(opcodeRaw)
            }
            let operandCount = try VarintCodec.decodeUnsigned(from: code, offset: &offset)
            var operands: [Int64] = []
            operands.reserveCapacity(Int(operandCount))
            for _ in 0..<operandCount {
                operands.append(try VarintCodec.decodeSigned(from: code, offset: &offset))
            }
            instructions.append(.init(opcode: opcode, operands: operands))
        }
        return instructions
    }
}

public enum DecodeError: Error, Sendable {
    case invalidOpcode(UInt8)
}
