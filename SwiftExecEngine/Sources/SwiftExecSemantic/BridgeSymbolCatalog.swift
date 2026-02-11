import Foundation

public struct BridgeSymbolCatalogEntry: Sendable, Hashable {
    public let symbolID: SymbolID
    public let name: String
    public let capability: String

    public init(symbolID: SymbolID, name: String, capability: String) {
        self.symbolID = symbolID
        self.name = name
        self.capability = capability
    }
}

public enum BridgeSymbolCatalog {
    // This table is intentionally deterministic and can be replaced by generated source.
    public static let entries: [BridgeSymbolCatalogEntry] = [
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.print), name: BuiltinSymbolName.print, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringUppercased), name: BuiltinSymbolName.stringUppercased, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringLowercased), name: BuiltinSymbolName.stringLowercased, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stringContains), name: BuiltinSymbolName.stringContains, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.intInit), name: BuiltinSymbolName.intInit, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.doubleInit), name: BuiltinSymbolName.doubleInit, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.boolInit), name: BuiltinSymbolName.boolInit, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.dateNow), name: BuiltinSymbolName.dateNow, capability: "dateFormatting"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.textInit), name: BuiltinSymbolName.textInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.buttonInit), name: BuiltinSymbolName.buttonInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.vStackInit), name: BuiltinSymbolName.vStackInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.hStackInit), name: BuiltinSymbolName.hStackInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.spacerInit), name: BuiltinSymbolName.spacerInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.imageInit), name: BuiltinSymbolName.imageInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.textFieldInit), name: BuiltinSymbolName.textFieldInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.toggleInit), name: BuiltinSymbolName.toggleInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.paddingModifier), name: BuiltinSymbolName.paddingModifier, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.fontModifier), name: BuiltinSymbolName.fontModifier, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.foregroundStyleModifier), name: BuiltinSymbolName.foregroundStyleModifier, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.frameModifier), name: BuiltinSymbolName.frameModifier, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.backgroundModifier), name: BuiltinSymbolName.backgroundModifier, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onTapHook), name: BuiltinSymbolName.onTapHook, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onAppearHook), name: BuiltinSymbolName.onAppearHook, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.onChangeHook), name: BuiltinSymbolName.onChangeHook, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateInit), name: BuiltinSymbolName.stateInit, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateGet), name: BuiltinSymbolName.stateGet, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateSet), name: BuiltinSymbolName.stateSet, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .bridge, name: BuiltinSymbolName.stateBind), name: BuiltinSymbolName.stateBind, capability: "swiftUIBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "+"), name: BuiltinOperatorName.add, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "-"), name: BuiltinOperatorName.subtract, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "*"), name: BuiltinOperatorName.multiply, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "/"), name: BuiltinOperatorName.divide, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "=="), name: BuiltinOperatorName.equal, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "<"), name: BuiltinOperatorName.less, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: ">"), name: BuiltinOperatorName.greater, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "<="), name: BuiltinOperatorName.lessOrEqual, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: ">="), name: BuiltinOperatorName.greaterOrEqual, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "&&"), name: BuiltinOperatorName.and, capability: "foundationBasic"),
        .init(symbolID: SymbolHasher.hash(namespace: .operator, name: "||"), name: BuiltinOperatorName.or, capability: "foundationBasic"),
    ]

    public static let byID: [SymbolID: BridgeSymbolCatalogEntry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.symbolID, $0) }
    )
}
