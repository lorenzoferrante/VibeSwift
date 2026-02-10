import Foundation
import SwiftExecSemantic

public struct CapabilitySet: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let foundationBasic = CapabilitySet(rawValue: 1 << 0)
    public static let dateFormatting = CapabilitySet(rawValue: 1 << 1)
    public static let swiftUIBasic = CapabilitySet(rawValue: 1 << 2)
    public static let diagnostics = CapabilitySet(rawValue: 1 << 3)

    public static let `default`: CapabilitySet = [.foundationBasic, .diagnostics]
    public static let unrestricted: CapabilitySet = [.foundationBasic, .dateFormatting, .swiftUIBasic, .diagnostics]
}

public enum SymbolPolicy {
    public static func isAllowed(symbolID: SymbolID, capabilities: CapabilitySet) -> Bool {
        guard let entry = BridgeSymbolCatalog.byID[symbolID] else {
            return false
        }

        switch entry.capability {
        case "foundationBasic":
            return capabilities.contains(.foundationBasic)
        case "dateFormatting":
            return capabilities.contains(.dateFormatting)
        case "swiftUIBasic":
            return capabilities.contains(.swiftUIBasic)
        default:
            return false
        }
    }
}
