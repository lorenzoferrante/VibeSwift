import Foundation
import SwiftExecDiagnostics
import SwiftOperators
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct ParsedSource: Sendable {
    public let sourceFile: SourceFileSyntax
    public let converter: SourceLocationConverter
    public let diagnostics: [EngineDiagnostic]

    public init(
        sourceFile: SourceFileSyntax,
        converter: SourceLocationConverter,
        diagnostics: [EngineDiagnostic]
    ) {
        self.sourceFile = sourceFile
        self.converter = converter
        self.diagnostics = diagnostics
    }
}

public enum SwiftSourceParser {
    public static func parse(source: String, fileName: String = "UserCode.swift") -> ParsedSource {
        let rawTree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: rawTree)

        let foldedTree: SourceFileSyntax
        do {
            let folded = try OperatorTable.standardOperators.foldAll(Syntax(rawTree))
            foldedTree = folded.as(SourceFileSyntax.self) ?? rawTree
        } catch {
            foldedTree = rawTree
        }

        let parserDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: rawTree)
        let diagnostics = parserDiagnostics.map { diagnostic -> EngineDiagnostic in
            let location = converter.location(for: diagnostic.position)
            let start = SourcePosition(
                line: location.line,
                column: location.column,
                utf8Offset: location.offset
            )
            return EngineDiagnostic(
                severity: .error,
                message: diagnostic.diagMessage.message,
                span: SourceSpan(start: start, end: start)
            )
        }

        return ParsedSource(
            sourceFile: foldedTree,
            converter: converter,
            diagnostics: diagnostics
        )
    }
}
