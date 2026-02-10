import Foundation
import SwiftExecDiagnostics

public struct Label: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct InstructionBuilder: Sendable {
    private var descriptors: [InstructionDescriptor] = []
    private var nextLabelID: Int = 0
    private var labelPositions: [Label: Int] = [:]
    private var jumpFixups: [(instructionIndex: Int, operandIndex: Int, label: Label)] = []

    public init() {}

    @discardableResult
    public mutating func emit(
        _ opcode: Opcode,
        operands: [Int64] = [],
        span: SourceSpan? = nil
    ) -> Int {
        descriptors.append(.init(opcode: opcode, operands: operands, span: span))
        return descriptors.count - 1
    }

    public mutating func createLabel() -> Label {
        defer { nextLabelID += 1 }
        return Label(rawValue: nextLabelID)
    }

    public mutating func mark(_ label: Label) {
        labelPositions[label] = descriptors.count
    }

    public mutating func emitJump(to label: Label, span: SourceSpan? = nil) {
        let instructionIndex = emit(.jump, operands: [-1], span: span)
        jumpFixups.append((instructionIndex: instructionIndex, operandIndex: 0, label: label))
    }

    public mutating func emitJumpIfFalse(to label: Label, span: SourceSpan? = nil) {
        let instructionIndex = emit(.jumpIfFalse, operands: [-1], span: span)
        jumpFixups.append((instructionIndex: instructionIndex, operandIndex: 0, label: label))
    }

    public mutating func emitJumpIfTrue(to label: Label, span: SourceSpan? = nil) {
        let instructionIndex = emit(.jumpIfTrue, operands: [-1], span: span)
        jumpFixups.append((instructionIndex: instructionIndex, operandIndex: 0, label: label))
    }

    public mutating func finish() throws -> [InstructionDescriptor] {
        for fixup in jumpFixups {
            guard let destination = labelPositions[fixup.label] else {
                throw BuilderError.unboundLabel(fixup.label.rawValue)
            }
            descriptors[fixup.instructionIndex].operands[fixup.operandIndex] = Int64(destination)
        }
        return descriptors
    }
}

public enum BuilderError: Error, Sendable {
    case unboundLabel(Int)
}
