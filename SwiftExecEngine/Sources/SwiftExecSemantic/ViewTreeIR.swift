import Foundation

public struct ViewTree: Sendable, Codable, Hashable {
    public var irVersion: Int
    public var capabilities: [String]
    public var root: ViewNode

    public init(
        irVersion: Int = 1,
        capabilities: [String] = [],
        root: ViewNode
    ) {
        self.irVersion = irVersion
        self.capabilities = capabilities
        self.root = root
    }
}

public struct ViewNode: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var props: [String: IRValue]
    public var children: [ViewNode]
    public var modifiers: [ViewNodeModifier]
    public var events: [ViewNodeEvent]

    public init(
        id: String,
        type: String,
        props: [String: IRValue] = [:],
        children: [ViewNode] = [],
        modifiers: [ViewNodeModifier] = [],
        events: [ViewNodeEvent] = []
    ) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
        self.modifiers = modifiers
        self.events = events
    }
}

public struct ViewNodeModifier: Sendable, Codable, Hashable {
    public var type: String
    public var params: [String: IRValue]

    public init(type: String, params: [String: IRValue] = [:]) {
        self.type = type
        self.params = params
    }
}

public struct ViewNodeEvent: Sendable, Codable, Hashable {
    public var event: String
    public var actionID: String
    public var path: String?

    public init(event: String, actionID: String, path: String? = nil) {
        self.event = event
        self.actionID = actionID
        self.path = path
    }
}

public enum IRValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([IRValue])
    case object([String: IRValue])
    case stateRef(path: String)
    case bindingRef(path: String)
}

extension IRValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case boolValue
        case intValue
        case doubleValue
        case stringValue
        case arrayValue
        case objectValue
        case path
    }

    private enum Kind: String, Codable {
        case null
        case bool
        case int
        case double
        case string
        case array
        case object
        case stateRef
        case bindingRef
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .null:
            self = .null
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        case .int:
            self = .int(try container.decode(Int64.self, forKey: .intValue))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .doubleValue))
        case .string:
            self = .string(try container.decode(String.self, forKey: .stringValue))
        case .array:
            self = .array(try container.decode([IRValue].self, forKey: .arrayValue))
        case .object:
            self = .object(try container.decode([String: IRValue].self, forKey: .objectValue))
        case .stateRef:
            self = .stateRef(path: try container.decode(String.self, forKey: .path))
        case .bindingRef:
            self = .bindingRef(path: try container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Kind.null, forKey: .type)
        case let .bool(value):
            try container.encode(Kind.bool, forKey: .type)
            try container.encode(value, forKey: .boolValue)
        case let .int(value):
            try container.encode(Kind.int, forKey: .type)
            try container.encode(value, forKey: .intValue)
        case let .double(value):
            try container.encode(Kind.double, forKey: .type)
            try container.encode(value, forKey: .doubleValue)
        case let .string(value):
            try container.encode(Kind.string, forKey: .type)
            try container.encode(value, forKey: .stringValue)
        case let .array(values):
            try container.encode(Kind.array, forKey: .type)
            try container.encode(values, forKey: .arrayValue)
        case let .object(values):
            try container.encode(Kind.object, forKey: .type)
            try container.encode(values, forKey: .objectValue)
        case let .stateRef(path):
            try container.encode(Kind.stateRef, forKey: .type)
            try container.encode(path, forKey: .path)
        case let .bindingRef(path):
            try container.encode(Kind.bindingRef, forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

public extension IRValue {
    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    public var intValue: Int64? {
        if case let .int(value) = self {
            return value
        }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        case let .int(value):
            return Double(value)
        default:
            return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .stateRef(path), let .bindingRef(path):
            return path
        default:
            return nil
        }
    }

    public static func fromRuntimeValue(_ value: RuntimeValue) -> IRValue? {
        switch value {
        case .none:
            return .null
        case let .bool(v):
            return .bool(v)
        case let .int64(v):
            return .int(v)
        case let .double(v):
            return .double(v)
        case let .string(v):
            return .string(v)
        case let .array(values):
            return .array(values.compactMap(IRValue.fromRuntimeValue))
        case let .dictionary(values):
            if let bindingPath = values["$binding"]?.stringValue {
                return .bindingRef(path: bindingPath)
            }
            if let statePath = values["$state"]?.stringValue {
                return .stateRef(path: statePath)
            }
            var result: [String: IRValue] = [:]
            for (key, runtime) in values {
                guard let decoded = IRValue.fromRuntimeValue(runtime) else {
                    continue
                }
                result[key] = decoded
            }
            return .object(result)
        case .native, .customInstance:
            return nil
        }
    }

    public var runtimeValue: RuntimeValue {
        switch self {
        case .null:
            return .none
        case let .bool(value):
            return .bool(value)
        case let .int(value):
            return .int64(value)
        case let .double(value):
            return .double(value)
        case let .string(value):
            return .string(value)
        case let .array(values):
            return .array(values.map(\.runtimeValue))
        case let .object(values):
            var mapped: [String: RuntimeValue] = [:]
            for (key, value) in values {
                mapped[key] = value.runtimeValue
            }
            return .dictionary(mapped)
        case let .stateRef(path):
            return .dictionary(["$state": .string(path)])
        case let .bindingRef(path):
            return .dictionary(["$binding": .string(path)])
        }
    }
}

public extension ViewTree {
    public static func fromRuntimeValue(
        _ value: RuntimeValue,
        defaultCapabilities: [String] = [],
        defaultIRVersion: Int = 1
    ) -> ViewTree? {
        // Full ViewTree payload shape:
        // {
        //   "irVersion": 1,
        //   "capabilities": ["swiftUIBasic"],
        //   "root": { ...node... }
        // }
        if let payload = value.dictionaryValue {
            if payload["root"] != nil {
                guard let rootRuntime = payload["root"],
                      let rootNode = ViewNode.fromRuntimeValue(rootRuntime) else {
                    return nil
                }
                let version = Int(payload["irVersion"]?.int64Value ?? Int64(defaultIRVersion))
                let capabilities = payload["capabilities"]?.arrayValue?.compactMap(\.stringValue) ?? defaultCapabilities
                return ViewTree(
                    irVersion: version,
                    capabilities: capabilities,
                    root: rootNode
                )
            }

            // Node-only payload shape (MVP convenience):
            // { "id": "...", "type": "...", ... }
            if payload["type"] != nil, let rootNode = ViewNode.fromRuntimeValue(value) {
                return ViewTree(
                    irVersion: defaultIRVersion,
                    capabilities: defaultCapabilities,
                    root: rootNode
                )
            }
        }

        return nil
    }
}

public extension ViewNode {
    public static func fromRuntimeValue(_ value: RuntimeValue) -> ViewNode? {
        guard let object = value.dictionaryValue else {
            return nil
        }
        guard let type = object["type"]?.stringValue else {
            return nil
        }

        var props: [String: IRValue] = [:]
        if let propsObject = object["props"]?.dictionaryValue {
            for (key, runtime) in propsObject {
                guard let decoded = IRValue.fromRuntimeValue(runtime) else {
                    continue
                }
                props[key] = decoded
            }
        }

        let children: [ViewNode] = object["children"]?.arrayValue?.compactMap(ViewNode.fromRuntimeValue) ?? []

        let modifiers: [ViewNodeModifier] = object["modifiers"]?.arrayValue?.compactMap { modifierValue in
            guard let modifierObject = modifierValue.dictionaryValue,
                  let modifierType = modifierObject["type"]?.stringValue else {
                return nil
            }
            let paramsObject = modifierObject["params"]?.dictionaryValue ?? modifierObject["props"]?.dictionaryValue ?? [:]
            var params: [String: IRValue] = [:]
            for (key, runtime) in paramsObject {
                guard let decoded = IRValue.fromRuntimeValue(runtime) else {
                    continue
                }
                params[key] = decoded
            }
            return ViewNodeModifier(type: modifierType, params: params)
        } ?? []

        let events: [ViewNodeEvent] = object["events"]?.arrayValue?.compactMap { eventValue in
            guard let eventObject = eventValue.dictionaryValue else {
                return nil
            }
            guard let eventName = eventObject["event"]?.stringValue,
                  let actionID = eventObject["actionID"]?.stringValue ?? eventObject["actionId"]?.stringValue else {
                return nil
            }
            let path = eventObject["path"]?.stringValue
            return ViewNodeEvent(event: eventName, actionID: actionID, path: path)
        } ?? []

        let explicitID = object["id"]?.stringValue
        let resolvedID: String
        if let explicitID, !explicitID.isEmpty {
            resolvedID = explicitID
        } else {
            let propsSignature = props.keys.sorted().joined(separator: ",")
            let childrenSignature = children.map(\.id).joined(separator: ",")
            let signature = "\(type)|\(propsSignature)|\(childrenSignature)"
            resolvedID = "node-\(SymbolHasher.hash(raw: signature))"
        }

        return ViewNode(
            id: resolvedID,
            type: type,
            props: props,
            children: children,
            modifiers: modifiers,
            events: events
        )
    }
}

private extension RuntimeValue {
    var arrayValue: [RuntimeValue]? {
        if case let .array(values) = self {
            return values
        }
        return nil
    }

    var dictionaryValue: [String: RuntimeValue]? {
        if case let .dictionary(values) = self {
            return values
        }
        return nil
    }
}
