import Foundation
import SwiftExecDiagnostics
import SwiftExecSecurity
import SwiftExecSemantic

public struct BridgeInvocationContext: Sendable {
    public let capabilities: CapabilitySet

    public init(capabilities: CapabilitySet) {
        self.capabilities = capabilities
    }
}

public enum BridgeRuntime {
    public static func invoke(
        symbolID: SymbolID,
        receiver: RuntimeValue?,
        args: [RuntimeValue],
        context: BridgeInvocationContext,
        printSink: (@Sendable (String) -> Void)?
    ) throws -> RuntimeValue {
        guard SymbolPolicy.isAllowed(symbolID: symbolID, capabilities: context.capabilities) else {
            throw RuntimeError(
                message: "Bridge symbol is not allowed by capabilities: \(symbolID)",
                symbolID: symbolID
            )
        }

        if let value = try GeneratedBridgeDispatch.invoke(
            symbolID: symbolID,
            receiver: receiver,
            args: args,
            printSink: printSink
        ) {
            return value
        }

        throw RuntimeError(
            message: "Unknown bridge symbol: \(symbolID)",
            symbolID: symbolID
        )
    }
}
