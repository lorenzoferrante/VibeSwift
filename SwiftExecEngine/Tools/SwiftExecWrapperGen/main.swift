import Foundation
import SwiftParser
import SwiftSyntax
import SwiftExecSemantic

@main
struct SwiftExecWrapperGen {
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        let cli = try CLI.parse(arguments: Array(arguments))
        let generator = WrapperGenerator(configuration: cli)
        try generator.run()
    }
}

private struct CLI {
    let interfacePaths: [String]
    let outputDirectory: String

    static func parse(arguments: [String]) throws -> CLI {
        var interfaces: [String] = []
        var outputDirectory: String?
        var idx = 0
        while idx < arguments.count {
            let token = arguments[idx]
            switch token {
            case "--interface":
                idx += 1
                guard idx < arguments.count else { throw CLIError.missingValue("--interface") }
                interfaces.append(arguments[idx])
            case "--output":
                idx += 1
                guard idx < arguments.count else { throw CLIError.missingValue("--output") }
                outputDirectory = arguments[idx]
            default:
                throw CLIError.unknownArgument(token)
            }
            idx += 1
        }

        guard !interfaces.isEmpty else {
            throw CLIError.missingValue("--interface")
        }
        guard let outputDirectory else {
            throw CLIError.missingValue("--output")
        }
        return CLI(interfacePaths: interfaces, outputDirectory: outputDirectory)
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .missingValue(flag):
            return "Missing value for \(flag)"
        case let .unknownArgument(arg):
            return "Unknown argument: \(arg)"
        }
    }
}

private struct WrapperMember: Hashable {
    enum Kind: String {
        case function
        case initializer
        case method
        case property
    }

    let module: String
    let typeName: String?
    let memberName: String
    let kind: Kind
    let arity: Int

    var symbolName: String {
        switch kind {
        case .function:
            return "\(module).\(memberName)"
        case .initializer:
            return "\(module).\(typeName ?? "_").init"
        case .method:
            return "\(module).\(typeName ?? "_").\(memberName)"
        case .property:
            return "\(module).\(typeName ?? "_").\(memberName)"
        }
    }
}

private final class WrapperGenerator {
    private let configuration: CLI

    init(configuration: CLI) {
        self.configuration = configuration
    }

    func run() throws {
        let members = try collectMembers(from: configuration.interfacePaths)
        let filtered = members.filter(allowlistContains)
        try FileManager.default.createDirectory(
            atPath: configuration.outputDirectory,
            withIntermediateDirectories: true
        )
        try writeSymbolTable(members: filtered)
        try writeDispatch(members: filtered)
    }

    private func collectMembers(from paths: [String]) throws -> [WrapperMember] {
        var result: Set<WrapperMember> = []
        for path in paths {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let file = Parser.parse(source: source)
            let collector = InterfaceCollector(sourcePath: path)
            collector.walk(Syntax(file))
            result.formUnion(collector.members)
        }
        return result.sorted { $0.symbolName < $1.symbolName }
    }

    private func allowlistContains(_ member: WrapperMember) -> Bool {
        Self.allowlist.contains(member.symbolName)
    }

    private func writeSymbolTable(members: [WrapperMember]) throws {
        let path = URL(fileURLWithPath: configuration.outputDirectory).appendingPathComponent("GeneratedSymbolTable.swift")
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("import SwiftExecSemantic")
        lines.append("")
        lines.append("// GENERATED FILE. DO NOT EDIT.")
        lines.append("public enum GeneratedSymbolTable {")
        for member in members {
            let constName = constantName(for: member.symbolName)
            lines.append("    public static let \(constName) = SymbolHasher.hash(namespace: .bridge, name: \"\(member.symbolName)\")")
        }
        lines.append("}")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    private func writeDispatch(members: [WrapperMember]) throws {
        let path = URL(fileURLWithPath: configuration.outputDirectory).appendingPathComponent("GeneratedBridgeDispatch.swift")
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("import SwiftExecDiagnostics")
        lines.append("import SwiftExecSemantic")
        lines.append("#if canImport(SwiftUI)")
        lines.append("import SwiftUI")
        lines.append("#endif")
        lines.append("")
        lines.append("// GENERATED FILE. DO NOT EDIT.")
        lines.append("public enum GeneratedBridgeDispatch {")
        lines.append("    public static func invoke(symbolID: SymbolID, receiver: RuntimeValue?, args: [RuntimeValue], printSink: (@Sendable (String) -> Void)?) throws -> RuntimeValue? {")
        lines.append("        switch symbolID {")
        for member in members {
            let constName = constantName(for: member.symbolName)
            lines.append("        case GeneratedSymbolTable.\(constName):")
            lines.append(contentsOf: dispatchBody(for: member).map { "            " + $0 })
        }
        lines.append("        default:")
        lines.append("            return nil")
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    private func dispatchBody(for member: WrapperMember) -> [String] {
        switch member.symbolName {
        case BuiltinSymbolName.print:
            return [
                "guard args.count == 1 else { throw RuntimeError(message: \"Swift.print expects 1 argument\", symbolID: symbolID) }",
                "printSink?(args[0].stringValue ?? String(describing: args[0]))",
                "return .none"
            ]
        case BuiltinSymbolName.stringUppercased:
            return [
                "guard let value = receiver?.stringValue else { throw RuntimeError(message: \"uppercased needs String receiver\", symbolID: symbolID) }",
                "return .string(value.uppercased())"
            ]
        case BuiltinSymbolName.stringLowercased:
            return [
                "guard let value = receiver?.stringValue else { throw RuntimeError(message: \"lowercased needs String receiver\", symbolID: symbolID) }",
                "return .string(value.lowercased())"
            ]
        case BuiltinSymbolName.stringContains:
            return [
                "guard let value = receiver?.stringValue, let needle = args.first?.stringValue else { throw RuntimeError(message: \"contains expects String receiver + String arg\", symbolID: symbolID) }",
                "return .bool(value.contains(needle))"
            ]
        case BuiltinSymbolName.intInit:
            return [
                "guard let value = args.first?.int64Value else { throw RuntimeError(message: \"Int.init expects numeric arg\", symbolID: symbolID) }",
                "return .int64(value)"
            ]
        case BuiltinSymbolName.doubleInit:
            return [
                "guard let value = args.first?.doubleValue else { throw RuntimeError(message: \"Double.init expects numeric arg\", symbolID: symbolID) }",
                "return .double(value)"
            ]
        case BuiltinSymbolName.boolInit:
            return [
                "guard let value = args.first?.boolValue else { throw RuntimeError(message: \"Bool.init expects bool arg\", symbolID: symbolID) }",
                "return .bool(value)"
            ]
        case BuiltinSymbolName.dateNow:
            return [
                "return .native(NativeBox(Date.now))"
            ]
        case BuiltinSymbolName.textInit:
            return [
                "#if canImport(SwiftUI)",
                "guard let text = args.first?.stringValue else { throw RuntimeError(message: \"Text.init expects String arg\", symbolID: symbolID) }",
                "return .native(NativeBox(AnyView(Text(text))))",
                "#else",
                "throw RuntimeError(message: \"SwiftUI unavailable\", symbolID: symbolID)",
                "#endif"
            ]
        default:
            return [
                "throw RuntimeError(message: \"No generated implementation for \(member.symbolName)\", symbolID: symbolID)"
            ]
        }
    }

    private func constantName(for symbolName: String) -> String {
        symbolName
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: "*", with: "mul")
            .replacingOccurrences(of: "/", with: "div")
            .replacingOccurrences(of: "<", with: "lt")
            .replacingOccurrences(of: ">", with: "gt")
            .replacingOccurrences(of: "=", with: "eq")
    }

    private static let allowlist: Set<String> = [
        BuiltinSymbolName.print,
        BuiltinSymbolName.stringUppercased,
        BuiltinSymbolName.stringLowercased,
        BuiltinSymbolName.stringContains,
        BuiltinSymbolName.intInit,
        BuiltinSymbolName.doubleInit,
        BuiltinSymbolName.boolInit,
        BuiltinSymbolName.dateNow,
        BuiltinSymbolName.textInit
    ]
}

private final class InterfaceCollector: SyntaxVisitor {
    private let moduleName: String
    private var typeStack: [String] = []
    private(set) var members: Set<WrapperMember> = []

    init(sourcePath: String) {
        let fileName = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        let module = fileName.split(separator: ".").first.map(String.init) ?? fileName
        moduleName = module
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        _ = typeStack.popLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let arity = node.signature.parameterClause.parameters.count
        let member = WrapperMember(
            module: moduleName,
            typeName: typeStack.last,
            memberName: node.name.text,
            kind: typeStack.isEmpty ? .function : .method,
            arity: arity
        )
        members.insert(member)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let arity = node.signature.parameterClause.parameters.count
        members.insert(
            .init(
                module: moduleName,
                typeName: typeStack.last,
                memberName: "init",
                kind: .initializer,
                arity: arity
            )
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            members.insert(
                .init(
                    module: moduleName,
                    typeName: typeStack.last,
                    memberName: pattern.identifier.text,
                    kind: .property,
                    arity: 0
                )
            )
        }
        return .skipChildren
    }
}
