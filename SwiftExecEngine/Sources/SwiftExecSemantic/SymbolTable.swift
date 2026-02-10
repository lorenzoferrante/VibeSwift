import Foundation

public struct LocalBinding: Sendable {
    public let name: String
    public let index: Int
    public let mutable: Bool

    public init(name: String, index: Int, mutable: Bool) {
        self.name = name
        self.index = index
        self.mutable = mutable
    }
}

public final class LexicalScope: @unchecked Sendable {
    private var scopes: [[String: LocalBinding]] = [[:]]
    private var nextLocalIndex: Int = 0

    public init() {}

    public func pushScope() {
        scopes.append([:])
    }

    @discardableResult
    public func popScope() -> [String: LocalBinding]? {
        guard scopes.count > 1 else { return nil }
        return scopes.popLast()
    }

    public func define(name: String, mutable: Bool) -> LocalBinding {
        let binding = LocalBinding(name: name, index: nextLocalIndex, mutable: mutable)
        nextLocalIndex += 1
        scopes[scopes.count - 1][name] = binding
        return binding
    }

    public func resolve(name: String) -> LocalBinding? {
        for scope in scopes.reversed() {
            if let binding = scope[name] {
                return binding
            }
        }
        return nil
    }

    public var localCount: Int {
        nextLocalIndex
    }
}

public final class ProgramSymbolTable: @unchecked Sendable {
    private(set) var typeIDsByName: [String: TypeID] = [:]
    private(set) var fieldIDsByKey: [String: FieldID] = [:]
    private(set) var functionIDsByName: [String: FunctionID] = [:]

    public init() {}

    public func typeID(for name: String) -> TypeID {
        if let existing = typeIDsByName[name] {
            return existing
        }
        let id = SymbolHasher.hash(namespace: .type, name: name)
        typeIDsByName[name] = id
        return id
    }

    public func fieldID(typeName: String, fieldName: String) -> FieldID {
        let key = "\(typeName).\(fieldName)"
        if let existing = fieldIDsByKey[key] {
            return existing
        }
        let id = SymbolHasher.hash(namespace: .field, name: key)
        fieldIDsByKey[key] = id
        return id
    }

    public func functionID(for name: String) -> FunctionID {
        if let existing = functionIDsByName[name] {
            return existing
        }
        let id = SymbolHasher.hash(namespace: .function, name: name)
        functionIDsByName[name] = id
        return id
    }

    public func bridgeSymbolID(for name: String) -> SymbolID {
        SymbolHasher.hash(namespace: .bridge, name: name)
    }

    public func operatorSymbolID(for op: String) -> SymbolID {
        SymbolHasher.hash(namespace: .operator, name: op)
    }

    public func lookupTypeID(named name: String) -> TypeID? {
        typeIDsByName[name]
    }

    public func lookupFunctionID(named name: String) -> FunctionID? {
        functionIDsByName[name]
    }
}
