import Foundation
import SwiftExecSemantic

public struct SourcePosition: Sendable, Codable, Hashable {
    public let line: Int
    public let column: Int
    public let utf8Offset: Int

    public init(line: Int, column: Int, utf8Offset: Int) {
        self.line = line
        self.column = column
        self.utf8Offset = utf8Offset
    }
}

public struct SourceSpan: Sendable, Codable, Hashable {
    public let start: SourcePosition
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }
}

public struct StackFrameDiagnostic: Sendable, Hashable {
    public let functionName: String
    public let span: SourceSpan?

    public init(functionName: String, span: SourceSpan?) {
        self.functionName = functionName
        self.span = span
    }
}

public struct EngineDiagnostic: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable {
        case error
        case warning
        case note
    }

    public let id: UUID
    public let severity: Severity
    public let message: String
    public let span: SourceSpan?

    public init(
        id: UUID = UUID(),
        severity: Severity,
        message: String,
        span: SourceSpan?
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.span = span
    }
}

public struct RuntimeError: Error, Sendable {
    public let message: String
    public let symbolID: SymbolID?
    public let failingInstructionIndex: Int?
    public let span: SourceSpan?
    public let callStack: [StackFrameDiagnostic]

    public init(
        message: String,
        symbolID: SymbolID? = nil,
        failingInstructionIndex: Int? = nil,
        span: SourceSpan? = nil,
        callStack: [StackFrameDiagnostic] = []
    ) {
        self.message = message
        self.symbolID = symbolID
        self.failingInstructionIndex = failingInstructionIndex
        self.span = span
        self.callStack = callStack
    }
}
