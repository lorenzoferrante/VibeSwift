import Foundation
import SwiftExecSemantic

public enum Constant: Hashable, Sendable {
    case none
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case string(String)
    case symbol(SymbolID)
    case type(TypeID)
    case field(FieldID)
    case function(FunctionID)
}

public struct ConstantPoolBuilder: Sendable {
    public private(set) var constants: [Constant] = []
    private var indices: [Constant: Int] = [:]

    public init() {}

    @discardableResult
    public mutating func intern(_ constant: Constant) -> Int {
        if let index = indices[constant] {
            return index
        }
        let index = constants.count
        constants.append(constant)
        indices[constant] = index
        return index
    }
}

public extension Constant {
    var debugDescription: String {
        switch self {
        case .none:
            return "none"
        case let .int64(value):
            return "int64(\(value))"
        case let .double(value):
            return "double(\(value))"
        case let .bool(value):
            return "bool(\(value))"
        case let .string(value):
            return "string(\(value))"
        case let .symbol(value):
            return "symbol(\(value))"
        case let .type(value):
            return "type(\(value))"
        case let .field(value):
            return "field(\(value))"
        case let .function(value):
            return "function(\(value))"
        }
    }
}
