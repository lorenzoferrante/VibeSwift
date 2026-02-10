import Foundation

public struct StructLayout: Sendable {
    public struct Field: Sendable {
        public let id: FieldID
        public let name: String
        public let typeHint: String?

        public init(id: FieldID, name: String, typeHint: String?) {
            self.id = id
            self.name = name
            self.typeHint = typeHint
        }
    }

    public let typeID: TypeID
    public let name: String
    public let fields: [Field]

    public init(typeID: TypeID, name: String, fields: [Field]) {
        self.typeID = typeID
        self.name = name
        self.fields = fields
    }

    public var fieldsByID: [FieldID: Field] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })
    }

    public var fieldsByName: [String: Field] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
    }
}

public struct FunctionSignature: Sendable {
    public let id: FunctionID
    public let name: String
    public let arity: Int

    public init(id: FunctionID, name: String, arity: Int) {
        self.id = id
        self.name = name
        self.arity = arity
    }
}

public struct ProgramSymbols: Sendable {
    public var structLayouts: [TypeID: StructLayout]
    public var functionSignatures: [FunctionID: FunctionSignature]

    public init(
        structLayouts: [TypeID: StructLayout] = [:],
        functionSignatures: [FunctionID: FunctionSignature] = [:]
    ) {
        self.structLayouts = structLayouts
        self.functionSignatures = functionSignatures
    }
}
