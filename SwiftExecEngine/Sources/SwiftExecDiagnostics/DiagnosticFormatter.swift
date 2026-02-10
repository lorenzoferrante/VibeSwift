import Foundation

public enum DiagnosticFormatter {
    public static func render(_ diagnostic: EngineDiagnostic) -> String {
        var parts: [String] = []
        parts.append("[\(diagnostic.severity.rawValue.uppercased())]")
        if let span = diagnostic.span {
            parts.append("L\(span.start.line):\(span.start.column)")
        }
        parts.append(diagnostic.message)
        return parts.joined(separator: " ")
    }

    public static func render(_ runtimeError: RuntimeError) -> String {
        var lines: [String] = [runtimeError.message]
        if let span = runtimeError.span {
            lines.append("at \(span.start.line):\(span.start.column)")
        }
        if !runtimeError.callStack.isEmpty {
            lines.append("stack trace:")
            for frame in runtimeError.callStack {
                if let span = frame.span {
                    lines.append("- \(frame.functionName) @ \(span.start.line):\(span.start.column)")
                } else {
                    lines.append("- \(frame.functionName)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
