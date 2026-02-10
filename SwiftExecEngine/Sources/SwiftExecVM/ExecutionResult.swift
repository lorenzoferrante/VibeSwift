import Foundation
import SwiftExecDiagnostics
import SwiftExecSemantic

public struct VMExecutionResult: Sendable {
    public let value: RuntimeValue
    public let diagnostics: [EngineDiagnostic]
    public let output: [String]

    public init(value: RuntimeValue, diagnostics: [EngineDiagnostic], output: [String]) {
        self.value = value
        self.diagnostics = diagnostics
        self.output = output
    }
}
