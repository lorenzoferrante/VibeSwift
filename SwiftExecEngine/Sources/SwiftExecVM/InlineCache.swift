import Foundation
import SwiftExecSemantic

public struct BridgeInlineCacheKey: Hashable, Sendable {
    public let instructionIndex: Int
    public let receiverType: String

    public init(instructionIndex: Int, receiverType: String) {
        self.instructionIndex = instructionIndex
        self.receiverType = receiverType
    }
}

public struct BridgeInlineCacheEntry: Sendable {
    public let symbolID: SymbolID

    public init(symbolID: SymbolID) {
        self.symbolID = symbolID
    }
}

public struct FieldInlineCacheKey: Hashable, Sendable {
    public let instructionIndex: Int
    public let typeID: TypeID
    public let fieldID: FieldID

    public init(instructionIndex: Int, typeID: TypeID, fieldID: FieldID) {
        self.instructionIndex = instructionIndex
        self.typeID = typeID
        self.fieldID = fieldID
    }
}

public struct VMInlineCaches: Sendable {
    public var bridge: [BridgeInlineCacheKey: BridgeInlineCacheEntry] = [:]
    public var fields: Set<FieldInlineCacheKey> = []

    public init() {}
}
