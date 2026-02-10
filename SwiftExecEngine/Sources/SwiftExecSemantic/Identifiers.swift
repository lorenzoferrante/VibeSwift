import Foundation

public typealias SymbolID = UInt32
public typealias TypeID = UInt32
public typealias FieldID = UInt32
public typealias FunctionID = UInt32

public enum SymbolNamespace: String, Sendable, CaseIterable {
    case function = "fn"
    case type = "type"
    case field = "field"
    case bridge = "bridge"
    case `operator` = "op"
}

public enum SymbolHasher {
    private static let offset: UInt32 = 2_166_136_261
    private static let prime: UInt32 = 16_777_619

    public static func hash(namespace: SymbolNamespace, name: String) -> SymbolID {
        hash(raw: "\(namespace.rawValue)::\(name)")
    }

    public static func hash(raw: String) -> SymbolID {
        var value = offset
        for byte in raw.utf8 {
            value ^= UInt32(byte)
            value = value &* prime
        }
        return value
    }
}

public enum BuiltinSymbolName {
    public static let print = "Swift.print"
    public static let stringUppercased = "Swift.String.uppercased"
    public static let stringLowercased = "Swift.String.lowercased"
    public static let stringContains = "Swift.String.contains"
    public static let intInit = "Swift.Int.init"
    public static let doubleInit = "Swift.Double.init"
    public static let boolInit = "Swift.Bool.init"
    public static let dateNow = "Foundation.Date.now"
    public static let textInit = "SwiftUI.Text.init"
}

public enum BuiltinOperatorName {
    public static let add = "operator.+"
    public static let subtract = "operator.-"
    public static let multiply = "operator.*"
    public static let divide = "operator./"
    public static let equal = "operator.=="
    public static let less = "operator.<"
    public static let greater = "operator.>"
    public static let lessOrEqual = "operator.<="
    public static let greaterOrEqual = "operator.>="
    public static let and = "operator.&&"
    public static let or = "operator.||"
}
