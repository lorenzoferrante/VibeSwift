import Foundation
import SwiftExecSemantic

public struct BridgeScriptContext {
    public var stateGet: (String) -> RuntimeValue
    public var stateSet: (String, RuntimeValue) -> Void
    public var stateBind: (String) -> RuntimeValue

    public init(
        stateGet: @escaping (String) -> RuntimeValue,
        stateSet: @escaping (String, RuntimeValue) -> Void,
        stateBind: @escaping (String) -> RuntimeValue
    ) {
        self.stateGet = stateGet
        self.stateSet = stateSet
        self.stateBind = stateBind
    }
}

private enum BridgeScriptContextStorage {
    static let lock = NSLock()
    static var stack: [BridgeScriptContext] = []

    static func push(_ context: BridgeScriptContext) {
        lock.lock()
        stack.append(context)
        lock.unlock()
    }

    static func pop() {
        lock.lock()
        if !stack.isEmpty {
            _ = stack.removeLast()
        }
        lock.unlock()
    }

    static var current: BridgeScriptContext? {
        lock.lock()
        defer { lock.unlock() }
        return stack.last
    }
}

public extension BridgeRuntime {
    static func withScriptContext<T>(
        _ context: BridgeScriptContext,
        _ operation: () throws -> T
    ) rethrows -> T {
        BridgeScriptContextStorage.push(context)
        defer { BridgeScriptContextStorage.pop() }
        return try operation()
    }

    static var currentScriptContext: BridgeScriptContext? {
        BridgeScriptContextStorage.current
    }
}
