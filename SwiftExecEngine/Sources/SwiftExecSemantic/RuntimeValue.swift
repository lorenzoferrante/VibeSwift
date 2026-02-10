import Foundation

public struct NativeBox: @unchecked Sendable, CustomStringConvertible {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public var description: String {
        String(describing: value)
    }
}

public struct CustomInstance: Sendable, CustomStringConvertible {
    public let typeID: TypeID
    public var fields: [FieldID: RuntimeValue]

    public init(typeID: TypeID, fields: [FieldID: RuntimeValue] = [:]) {
        self.typeID = typeID
        self.fields = fields
    }

    public var description: String {
        "CustomInstance(typeID: \(typeID), fields: \(fields))"
    }
}

public enum RuntimeValue: Sendable, CustomStringConvertible {
    case none
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array([RuntimeValue])
    case dictionary([String: RuntimeValue])
    case native(NativeBox)
    case customInstance(CustomInstance)

    public var description: String {
        switch self {
        case .none:
            return "nil"
        case let .int64(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case let .string(value):
            return value
        case let .array(values):
            return values.description
        case let .dictionary(values):
            return values.description
        case let .native(box):
            return box.description
        case let .customInstance(instance):
            return instance.description
        }
    }

    public var truthyValue: Bool {
        switch self {
        case .none:
            return false
        case let .bool(value):
            return value
        case let .int64(value):
            return value != 0
        case let .double(value):
            return value != 0
        case let .string(value):
            return !value.isEmpty
        case let .array(values):
            return !values.isEmpty
        case let .dictionary(values):
            return !values.isEmpty
        case .native, .customInstance:
            return true
        }
    }

    public var int64Value: Int64? {
        switch self {
        case let .int64(value):
            return value
        case let .double(value):
            return Int64(value)
        case let .string(value):
            return Int64(value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        case let .int64(value):
            return Double(value)
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .int64(value):
            return value != 0
        case let .double(value):
            return value != 0
        case let .string(value):
            switch value.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .int64(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case .none:
            return "nil"
        case let .native(box):
            return String(describing: box.value)
        case .array, .dictionary, .customInstance:
            return nil
        }
    }

    public var nativeValue: Any? {
        if case let .native(box) = self {
            return box.value
        }
        return nil
    }
}
