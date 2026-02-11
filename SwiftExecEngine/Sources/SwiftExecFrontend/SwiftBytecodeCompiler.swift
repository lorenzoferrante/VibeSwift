import Foundation
import SwiftExecBytecode
import SwiftExecDiagnostics
import SwiftExecSemantic
import SwiftParser
import SwiftSyntax

public struct CompilationOutput: Sendable {
    public let program: BytecodeProgram?
    public let diagnostics: [EngineDiagnostic]

    public init(program: BytecodeProgram?, diagnostics: [EngineDiagnostic]) {
        self.program = program
        self.diagnostics = diagnostics
    }
}

public enum SwiftBytecodeCompiler {
    public static func compile(source: String, fileName: String = "UserCode.swift") -> CompilationOutput {
        let parsed = SwiftSourceParser.parse(source: source, fileName: fileName)
        let compiler = ProgramCompiler(parsed: parsed)
        return compiler.compile()
    }
}

private final class ProgramCompiler {
    private let parsed: ParsedSource
    private let symbols = ProgramSymbolTable()
    private var diagnostics: [EngineDiagnostic] = []
    private var constantPool = ConstantPoolBuilder()

    private var functionDecls: [FunctionDeclSyntax] = []
    private var structDecls: [StructDeclSyntax] = []
    private var topLevelItems: [CodeBlockItemSyntax] = []

    private var structLayouts: [TypeID: StructLayout] = [:]
    private var functionMetas: [FunctionMeta] = []

    init(parsed: ParsedSource) {
        self.parsed = parsed
        self.diagnostics = parsed.diagnostics
    }

    func compile() -> CompilationOutput {
        collectTopLevelItems()
        registerStructs()
        registerFunctions()

        do {
            let entry = try compileEntryFunction()
            var allFunctions = [entry]
            for functionDecl in functionDecls {
                allFunctions.append(try compileFunctionDecl(functionDecl))
            }

            var mergedInstructions: [InstructionDescriptor] = []
            var emittedFunctionMetas: [FunctionMeta] = []

            for (idx, compiled) in allFunctions.enumerated() {
                let start = mergedInstructions.count
                let adjusted = adjustInstructionTargets(compiled.instructions, by: start)
                mergedInstructions.append(contentsOf: adjusted)
                emittedFunctionMetas.append(
                    .init(
                        id: compiled.id,
                        name: compiled.name,
                        entryInstructionIndex: start,
                        arity: compiled.arity,
                        localCount: compiled.localCount,
                        isEntryPoint: idx == 0
                    )
                )
            }

            var programSymbols = ProgramSymbols()
            programSymbols.structLayouts = structLayouts
            programSymbols.functionSignatures = Dictionary(
                uniqueKeysWithValues: emittedFunctionMetas.map {
                    ($0.id, .init(id: $0.id, name: $0.name, arity: $0.arity))
                }
            )

            let program = BytecodeAssembler.assemble(
                descriptors: mergedInstructions,
                constants: constantPool.constants,
                functions: emittedFunctionMetas,
                symbols: programSymbols
            )
            return .init(program: program, diagnostics: diagnostics)
        } catch let error as RuntimeError {
            diagnostics.append(.init(severity: .error, message: error.message, span: error.span))
            return .init(program: nil, diagnostics: diagnostics)
        } catch {
            diagnostics.append(.init(severity: .error, message: String(describing: error), span: nil))
            return .init(program: nil, diagnostics: diagnostics)
        }
    }

    private func collectTopLevelItems() {
        for item in parsed.sourceFile.statements {
            topLevelItems.append(item)
            if let functionDecl = item.item.as(FunctionDeclSyntax.self) {
                functionDecls.append(functionDecl)
            } else if let structDecl = item.item.as(StructDeclSyntax.self) {
                structDecls.append(structDecl)
            }
        }
    }

    private func registerStructs() {
        for structDecl in structDecls {
            let typeName = structDecl.name.text
            let typeID = symbols.typeID(for: typeName)
            var fields: [StructLayout.Field] = []
            for member in structDecl.memberBlock.members {
                guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
                    continue
                }
                for binding in variableDecl.bindings {
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                        continue
                    }
                    let fieldName = pattern.identifier.text
                    let fieldID = symbols.fieldID(typeName: typeName, fieldName: fieldName)
                    let typeHint = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    fields.append(.init(id: fieldID, name: fieldName, typeHint: typeHint))
                }
            }
            structLayouts[typeID] = .init(typeID: typeID, name: typeName, fields: fields)
        }
    }

    private func registerFunctions() {
        for functionDecl in functionDecls {
            _ = symbols.functionID(for: functionDecl.name.text)
        }
    }

    private func compileEntryFunction() throws -> CompiledFunction {
        let functionID = symbols.functionID(for: "__entry")
        let fnCompiler = FunctionCompiler(
            parsed: parsed,
            symbols: symbols,
            structLayouts: structLayouts,
            constantPool: constantPool
        )
        for item in topLevelItems {
            if item.item.is(FunctionDeclSyntax.self) || item.item.is(StructDeclSyntax.self) {
                continue
            }
            try fnCompiler.compileTopLevelItem(item)
        }
        try fnCompiler.emitImplicitReturnIfNeeded()
        constantPool = fnCompiler.constantPool
        return .init(
            id: functionID,
            name: "__entry",
            arity: 0,
            localCount: fnCompiler.localCount,
            instructions: try fnCompiler.finishInstructions()
        )
    }

    private func compileFunctionDecl(_ decl: FunctionDeclSyntax) throws -> CompiledFunction {
        let functionID = symbols.functionID(for: decl.name.text)
        let arity = decl.signature.parameterClause.parameters.count
        let fnCompiler = FunctionCompiler(
            parsed: parsed,
            symbols: symbols,
            structLayouts: structLayouts,
            constantPool: constantPool
        )

        for parameter in decl.signature.parameterClause.parameters {
            let localName = parameter.secondName?.text ?? parameter.firstName.text
            _ = fnCompiler.scope.define(name: localName, mutable: true)
        }

        if let body = decl.body {
            try fnCompiler.compileCodeBlockItems(body.statements)
        }
        try fnCompiler.emitImplicitReturnIfNeeded()
        constantPool = fnCompiler.constantPool
        return .init(
            id: functionID,
            name: decl.name.text,
            arity: arity,
            localCount: fnCompiler.localCount,
            instructions: try fnCompiler.finishInstructions()
        )
    }

    private func adjustInstructionTargets(
        _ descriptors: [InstructionDescriptor],
        by offset: Int
    ) -> [InstructionDescriptor] {
        descriptors.map { descriptor in
            guard descriptor.opcode == .jump ||
                    descriptor.opcode == .jumpIfFalse ||
                    descriptor.opcode == .jumpIfTrue,
                  let first = descriptor.operands.first else {
                return descriptor
            }
            var operands = descriptor.operands
            operands[0] = first + Int64(offset)
            return .init(opcode: descriptor.opcode, operands: operands, span: descriptor.span)
        }
    }
}

private struct CompiledFunction {
    let id: FunctionID
    let name: String
    let arity: Int
    let localCount: Int
    let instructions: [InstructionDescriptor]
}

private final class FunctionCompiler {
    private let parsed: ParsedSource
    private let symbols: ProgramSymbolTable
    private let structLayouts: [TypeID: StructLayout]
    private var builder = InstructionBuilder()
    private var localTypeHints: [Int: TypeID] = [:]
    let scope = LexicalScope()

    var constantPool: ConstantPoolBuilder

    init(
        parsed: ParsedSource,
        symbols: ProgramSymbolTable,
        structLayouts: [TypeID: StructLayout],
        constantPool: ConstantPoolBuilder
    ) {
        self.parsed = parsed
        self.symbols = symbols
        self.structLayouts = structLayouts
        self.constantPool = constantPool
    }

    var localCount: Int {
        scope.localCount
    }

    func finishInstructions() throws -> [InstructionDescriptor] {
        try builder.finish()
    }

    func compileTopLevelItem(_ item: CodeBlockItemSyntax) throws {
        if let statement = item.item.as(StmtSyntax.self) {
            try compileStatement(statement)
            return
        }
        if let expression = item.item.as(ExprSyntax.self) {
            let span = spanFor(expression)
            if try compileAssignmentIfNeeded(expression, span: span) {
                return
            }
            try compileExpression(expression, span: span)
            builder.emit(.pop, span: span)
            return
        }
        if let declaration = item.item.as(DeclSyntax.self),
           let variableDecl = declaration.as(VariableDeclSyntax.self) {
            try compileVariableDecl(variableDecl)
        }
    }

    func compileCodeBlockItems(_ statements: CodeBlockItemListSyntax) throws {
        for item in statements {
            if let statement = item.item.as(StmtSyntax.self) {
                try compileStatement(statement)
            } else if let declaration = item.item.as(DeclSyntax.self),
                      let variableDecl = declaration.as(VariableDeclSyntax.self) {
                try compileVariableDecl(variableDecl)
            } else if let expression = item.item.as(ExprSyntax.self) {
                let span = spanFor(expression)
                if try compileAssignmentIfNeeded(expression, span: span) {
                    continue
                }
                try compileExpression(expression, span: span)
                builder.emit(.pop, span: span)
            }
        }
    }

    func emitImplicitReturnIfNeeded() throws {
        let noneIndex = constantPool.intern(.none)
        builder.emit(.pushConst, operands: [Int64(noneIndex)], span: nil)
        builder.emit(.returnValue, span: nil)
    }

    private func compileStatement(_ stmt: StmtSyntax) throws {
        if let returnStmt = stmt.as(ReturnStmtSyntax.self) {
            let span = spanFor(returnStmt)
            if let expression = returnStmt.expression {
                try compileExpression(expression, span: span)
            } else {
                let noneIndex = constantPool.intern(.none)
                builder.emit(.pushConst, operands: [Int64(noneIndex)], span: span)
            }
            builder.emit(.returnValue, span: span)
            return
        }

        if let whileStmt = stmt.as(WhileStmtSyntax.self) {
            try compileWhileStmt(whileStmt)
            return
        }

        if let expressionStmt = stmt.as(ExpressionStmtSyntax.self) {
            let span = spanFor(expressionStmt)
            if try compileAssignmentIfNeeded(expressionStmt.expression, span: span) {
                return
            }
            try compileExpression(expressionStmt.expression, span: span)
            builder.emit(.pop, span: span)
            return
        }
    }

    private func compileVariableDecl(_ decl: VariableDeclSyntax) throws {
        let isMutable = decl.bindingSpecifier.tokenKind == .keyword(.var)
        for binding in decl.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            let local = scope.define(name: pattern.identifier.text, mutable: isMutable)
            let span = spanFor(binding)

            if let initializer = binding.initializer {
                try compileExpression(initializer.value, span: span)
            } else {
                let noneIndex = constantPool.intern(.none)
                builder.emit(.pushConst, operands: [Int64(noneIndex)], span: span)
            }
            builder.emit(.storeLocal, operands: [Int64(local.index)], span: span)

            if let initializer = binding.initializer,
               let inferred = inferredTypeID(for: initializer.value) {
                localTypeHints[local.index] = inferred
            }
        }
    }

    private func compileIfExpr(_ ifExpr: IfExprSyntax) throws {
        guard let firstCondition = ifExpr.conditions.first,
              let conditionExpr = extractConditionExpression(from: firstCondition) else {
            throw RuntimeError(message: "Unsupported if condition", span: spanFor(ifExpr))
        }
        let span = spanFor(ifExpr)
        let elseLabel = builder.createLabel()
        let endLabel = builder.createLabel()

        try compileExpression(conditionExpr, span: span)
        builder.emitJumpIfFalse(to: elseLabel, span: span)

        try compileCodeBlockItems(ifExpr.body.statements)
        builder.emitJump(to: endLabel, span: span)

        builder.mark(elseLabel)
        if let elseBody = ifExpr.elseBody {
            switch elseBody {
            case let .ifExpr(nested):
                try compileIfExpr(nested)
            case let .codeBlock(codeBlock):
                try compileCodeBlockItems(codeBlock.statements)
            }
        }

        builder.mark(endLabel)
    }

    private func compileWhileStmt(_ whileStmt: WhileStmtSyntax) throws {
        guard let firstCondition = whileStmt.conditions.first,
              let conditionExpr = extractConditionExpression(from: firstCondition) else {
            throw RuntimeError(message: "Unsupported while condition", span: spanFor(whileStmt))
        }
        let span = spanFor(whileStmt)
        let loopStart = builder.createLabel()
        let loopEnd = builder.createLabel()
        builder.mark(loopStart)
        try compileExpression(conditionExpr, span: span)
        builder.emitJumpIfFalse(to: loopEnd, span: span)
        try compileCodeBlockItems(whileStmt.body.statements)
        builder.emitJump(to: loopStart, span: span)
        builder.mark(loopEnd)
    }

    @discardableResult
    private func compileAssignmentIfNeeded(_ expression: ExprSyntax, span: SourceSpan?) throws -> Bool {
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            let isAssignment = infix.operator.as(AssignmentExprSyntax.self) != nil
                || infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "="
            if isAssignment {
                try compileAssignment(lhs: infix.leftOperand, rhs: infix.rightOperand, span: span)
                return true
            }
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           sequence.elements.count == 3 {
            let elements = Array(sequence.elements)
            guard let lhs = elements.first,
                  elements[1].as(AssignmentExprSyntax.self) != nil,
                  let rhs = elements.last else {
                return false
            }
            try compileAssignment(lhs: lhs, rhs: rhs, span: span)
            return true
        }

        if let parsed = parseTextualAssignment(from: expression.trimmedDescription) {
            try compileAssignment(lhs: parsed.lhs, rhs: parsed.rhs, span: span)
            return true
        }
        return false
    }

    private func compileAssignment(lhs: ExprSyntax, rhs: ExprSyntax, span: SourceSpan?) throws {
        if let identifier = lhs.as(DeclReferenceExprSyntax.self),
           let binding = scope.resolve(name: identifier.baseName.text) {
            try compileExpression(rhs, span: span)
            builder.emit(.dup, span: span)
            builder.emit(.storeLocal, operands: [Int64(binding.index)], span: span)
            if let inferred = inferredTypeID(for: rhs) {
                localTypeHints[binding.index] = inferred
            }
            return
        }

        if let member = lhs.as(MemberAccessExprSyntax.self),
           let base = member.base,
           let baseRef = base.as(DeclReferenceExprSyntax.self),
           let binding = scope.resolve(name: baseRef.baseName.text) {
            let localType = localTypeHints[binding.index]
            let fieldID = resolveFieldID(baseTypeID: localType, fieldName: member.declName.baseName.text)
            builder.emit(.loadLocal, operands: [Int64(binding.index)], span: span)
            try compileExpression(rhs, span: span)
            builder.emit(.setField, operands: [Int64(fieldID)], span: span)
            builder.emit(.storeLocal, operands: [Int64(binding.index)], span: span)
            return
        }

        throw RuntimeError(message: "Unsupported assignment target", span: span)
    }

    private func compileExpression(_ expression: ExprSyntax, span: SourceSpan?) throws {
        if let integerLiteral = expression.as(IntegerLiteralExprSyntax.self) {
            let value = Int64(integerLiteral.literal.text) ?? 0
            let index = constantPool.intern(.int64(value))
            builder.emit(.pushConst, operands: [Int64(index)], span: span)
            return
        }
        if let floatLiteral = expression.as(FloatLiteralExprSyntax.self) {
            let value = Double(floatLiteral.literal.text) ?? 0
            let index = constantPool.intern(.double(value))
            builder.emit(.pushConst, operands: [Int64(index)], span: span)
            return
        }
        if let boolLiteral = expression.as(BooleanLiteralExprSyntax.self) {
            let value = boolLiteral.literal.tokenKind == .keyword(.true)
            let index = constantPool.intern(.bool(value))
            builder.emit(.pushConst, operands: [Int64(index)], span: span)
            return
        }
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            let value = parseStringLiteral(stringLiteral)
            let index = constantPool.intern(.string(value))
            builder.emit(.pushConst, operands: [Int64(index)], span: span)
            return
        }
        if expression.is(NilLiteralExprSyntax.self) {
            let index = constantPool.intern(.none)
            builder.emit(.pushConst, operands: [Int64(index)], span: span)
            return
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            guard let binding = scope.resolve(name: reference.baseName.text) else {
                throw RuntimeError(message: "Unknown identifier: \(reference.baseName.text)", span: span)
            }
            builder.emit(.loadLocal, operands: [Int64(binding.index)], span: span)
            return
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let operatorExpr = infix.operator.as(BinaryOperatorExprSyntax.self) {
            let opName = operatorExpr.operator.text
            try compileExpression(infix.leftOperand, span: spanFor(infix.leftOperand))
            try compileExpression(infix.rightOperand, span: spanFor(infix.rightOperand))
            let symbolID = symbols.operatorSymbolID(for: opName)
            builder.emit(.callBridge, operands: [Int64(symbolID), 2, 0], span: span)
            return
        }
        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            try compileFunctionCall(functionCall, span: span)
            return
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            try compileMemberAccess(member, span: span)
            return
        }
        if let ifExpr = expression.as(IfExprSyntax.self) {
            try compileIfExpr(ifExpr)
            return
        }

        throw RuntimeError(message: "Unsupported expression: \(expression.trimmedDescription)", span: span)
    }

    private func compileFunctionCall(_ call: FunctionCallExprSyntax, span: SourceSpan?) throws {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base != nil {
            guard let base = member.base else {
                throw RuntimeError(message: "Method call missing base", span: span)
            }
            try compileExpression(base, span: spanFor(base))
            for argument in call.arguments {
                try compileExpression(argument.expression, span: spanFor(argument.expression))
            }
            let symbolID = symbolForMethod(name: member.declName.baseName.text)
            builder.emit(.callBridge, operands: [Int64(symbolID), Int64(call.arguments.count), 1], span: span)
            return
        }

        if let calleeRef = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let calleeName = calleeRef.baseName.text

            if let functionBinding = symbols.lookupFunctionID(named: calleeName) {
                for argument in call.arguments {
                    try compileExpression(argument.expression, span: spanFor(argument.expression))
                }
                builder.emit(.callUser, operands: [Int64(functionBinding), Int64(call.arguments.count)], span: span)
                return
            }

            if let structTypeID = symbols.lookupTypeID(named: calleeName),
               let layout = structLayouts[structTypeID] {
                let argumentList = Array(call.arguments)
                let count = min(layout.fields.count, argumentList.count)
                for idx in 0..<count {
                    try compileExpression(argumentList[idx].expression, span: spanFor(argumentList[idx].expression))
                }
                var operands: [Int64] = [Int64(structTypeID), Int64(count)]
                operands.append(contentsOf: layout.fields.prefix(count).map { Int64($0.id) })
                builder.emit(.makeStruct, operands: operands, span: span)
                return
            }

            for argument in call.arguments {
                try compileExpression(argument.expression, span: spanFor(argument.expression))
            }
            let symbolID = symbolForFunction(name: calleeName)
            builder.emit(.callBridge, operands: [Int64(symbolID), Int64(call.arguments.count), 0], span: span)
            return
        }

        throw RuntimeError(message: "Unsupported function call target", span: span)
    }

    private func compileMemberAccess(_ member: MemberAccessExprSyntax, span: SourceSpan?) throws {
        if let base = member.base {
            if let baseRef = base.as(DeclReferenceExprSyntax.self) {
                let symbolID = symbolForStaticMember(
                    base: baseRef.baseName.text,
                    member: member.declName.baseName.text
                )
                if symbolID == SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.dateNow) {
                    builder.emit(.callBridge, operands: [Int64(symbolID), 0, 0], span: span)
                    return
                }
            }
            if let baseRef = base.as(DeclReferenceExprSyntax.self),
               let binding = scope.resolve(name: baseRef.baseName.text) {
                let fieldID = resolveFieldID(
                    baseTypeID: localTypeHints[binding.index],
                    fieldName: member.declName.baseName.text
                )
                builder.emit(.loadLocal, operands: [Int64(binding.index)], span: span)
                builder.emit(.getField, operands: [Int64(fieldID)], span: span)
                return
            }
            try compileExpression(base, span: spanFor(base))
            let symbolID = symbolForStaticMember(base: nil, member: member.declName.baseName.text)
            builder.emit(.callBridge, operands: [Int64(symbolID), 0, 1], span: span)
            return
        }

        if member.declName.baseName.text == "now" {
            let symbolID = SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.dateNow)
            builder.emit(.callBridge, operands: [Int64(symbolID), 0, 0], span: span)
            return
        }

        throw RuntimeError(message: "Unsupported member access: \(member.trimmedDescription)", span: span)
    }

    private func symbolForFunction(name: String) -> SymbolID {
        switch name {
        case "print":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.print)
        case "Int":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.intInit)
        case "Double":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.doubleInit)
        case "Bool":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.boolInit)
        case "Text":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.textInit)
        case "Button":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.buttonInit)
        case "VStack":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.vStackInit)
        case "HStack":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.hStackInit)
        case "Spacer":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.spacerInit)
        case "Image":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.imageInit)
        case "TextField":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.textFieldInit)
        case "Toggle":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.toggleInit)
        case "padding":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.paddingModifier)
        case "font":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.fontModifier)
        case "foregroundStyle":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.foregroundStyleModifier)
        case "frame":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.frameModifier)
        case "background":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.backgroundModifier)
        case "onTap":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onTapHook)
        case "onAppear":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onAppearHook)
        case "onChange":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onChangeHook)
        case "State":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateInit)
        case "stateGet":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateGet)
        case "stateSet":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateSet)
        case "stateBind":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateBind)
        default:
            return symbols.bridgeSymbolID(for: "dynamic.\(name)")
        }
    }

    private func symbolForMethod(name: String) -> SymbolID {
        switch name {
        case "uppercased":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringUppercased)
        case "lowercased":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringLowercased)
        case "contains":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringContains)
        case "get":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateGet)
        case "set":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateSet)
        case "bind", "bindBool", "bindString", "bindDouble":
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateBind)
        default:
            return symbols.bridgeSymbolID(for: "dynamic.method.\(name)")
        }
    }

    private func symbolForStaticMember(base: String?, member: String) -> SymbolID {
        if base == "Date", member == "now" {
            return SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.dateNow)
        }
        return symbols.bridgeSymbolID(for: "dynamic.member.\(base ?? "_").\(member)")
    }

    private func inferredTypeID(for expression: ExprSyntax) -> TypeID? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let calleeRef = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return symbols.lookupTypeID(named: calleeRef.baseName.text)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self),
           let binding = scope.resolve(name: reference.baseName.text) {
            return localTypeHints[binding.index]
        }
        return nil
    }

    private func resolveFieldID(baseTypeID: TypeID?, fieldName: String) -> FieldID {
        if let baseTypeID, let layout = structLayouts[baseTypeID] {
            return symbols.fieldID(typeName: layout.name, fieldName: fieldName)
        }
        return symbols.fieldID(typeName: "*", fieldName: fieldName)
    }

    private func extractConditionExpression(from condition: ConditionElementSyntax) -> ExprSyntax? {
        switch condition.condition {
        case let .expression(expr):
            return ExprSyntax(expr)
        default:
            return nil
        }
    }

    private func parseStringLiteral(_ literal: StringLiteralExprSyntax) -> String {
        if literal.segments.count == 1,
           let segment = literal.segments.first?.as(StringSegmentSyntax.self) {
            return segment.content.text
        }
        let raw = literal.description
        if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    private func parseTextualAssignment(from text: String) -> (lhs: ExprSyntax, rhs: ExprSyntax)? {
        guard let assignmentIndex = findAssignmentIndex(in: text) else {
            return nil
        }
        let lhsText = String(text[..<assignmentIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsStart = text.index(after: assignmentIndex)
        let rhsText = String(text[rhsStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lhsText.isEmpty, !rhsText.isEmpty,
              let lhsExpr = parseExpressionSource(lhsText),
              let rhsExpr = parseExpressionSource(rhsText) else {
            return nil
        }
        return (lhs: lhsExpr, rhs: rhsExpr)
    }

    private func findAssignmentIndex(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "=" {
                let prev = index > text.startIndex ? text[text.index(before: index)] : "\0"
                let nextIndex = text.index(after: index)
                let next = nextIndex < text.endIndex ? text[nextIndex] : "\0"
                if prev != "=" && prev != "<" && prev != ">" && prev != "!" && next != "=" {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func parseExpressionSource(_ source: String) -> ExprSyntax? {
        let file = Parser.parse(source: source)
        guard let firstItem = file.statements.first else {
            return nil
        }
        if let expression = firstItem.item.as(ExprSyntax.self) {
            return expression
        }
        if let statement = firstItem.item.as(ExpressionStmtSyntax.self) {
            return statement.expression
        }
        return nil
    }

    private func spanFor(_ syntax: some SyntaxProtocol) -> SourceSpan? {
        SourceSpanBuilder.span(for: syntax, converter: parsed.converter)
    }
}
