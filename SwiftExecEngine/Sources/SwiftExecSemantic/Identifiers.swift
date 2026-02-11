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

    // SwiftLite UI DSL + runtime store hooks.
    public static let buttonInit = "SwiftLite.UI.Button"
    public static let vStackInit = "SwiftLite.UI.VStack"
    public static let hStackInit = "SwiftLite.UI.HStack"
    public static let spacerInit = "SwiftLite.UI.Spacer"
    public static let imageInit = "SwiftLite.UI.Image"
    public static let textFieldInit = "SwiftLite.UI.TextField"
    public static let toggleInit = "SwiftLite.UI.Toggle"

    public static let paddingModifier = "SwiftLite.UI.padding"
    public static let fontModifier = "SwiftLite.UI.font"
    public static let foregroundStyleModifier = "SwiftLite.UI.foregroundStyle"
    public static let frameModifier = "SwiftLite.UI.frame"
    public static let backgroundModifier = "SwiftLite.UI.background"

    public static let onTapHook = "SwiftLite.UI.onTap"
    public static let onAppearHook = "SwiftLite.UI.onAppear"
    public static let onChangeHook = "SwiftLite.UI.onChange"

    public static let stateInit = "SwiftLite.State.init"
    public static let stateGet = "SwiftLite.State.get"
    public static let stateSet = "SwiftLite.State.set"
    public static let stateBind = "SwiftLite.State.bind"
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
