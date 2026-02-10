import Foundation
import SwiftExecDiagnostics
import SwiftSyntax

public enum SourceSpanBuilder {
    public static func span(
        for syntax: some SyntaxProtocol,
        converter: SourceLocationConverter
    ) -> SourceSpan? {
        let startLoc = converter.location(for: syntax.positionAfterSkippingLeadingTrivia)
        let endLoc = converter.location(for: syntax.endPositionBeforeTrailingTrivia)
        let start = SourcePosition(
            line: startLoc.line,
            column: startLoc.column,
            utf8Offset: startLoc.offset
        )
        let end = SourcePosition(
            line: endLoc.line,
            column: endLoc.column,
            utf8Offset: endLoc.offset
        )
        return SourceSpan(start: start, end: end)
    }
}
