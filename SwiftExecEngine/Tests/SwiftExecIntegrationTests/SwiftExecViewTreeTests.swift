import SwiftExecBridgeRuntime
import SwiftExecHost
import SwiftExecSecurity
import SwiftExecSemantic
import XCTest

final class SwiftExecViewTreeTests: XCTestCase {
    func testUIDSLReturnsDecodableViewTree() {
        let source = """
func body() {
    let root = VStack(
        10,
        Text("Hello"),
        Button("Save", "saveTapped")
    )
    return padding(root, 8)
}
return body()
"""
        let engine = Engine()
        let result = engine.compileAndRun(
            .init(
                source: source,
                capabilities: [.foundationBasic, .diagnostics, .swiftUIBasic]
            )
        )

        switch result {
        case let .success(success):
            guard let tree = ViewTree.fromRuntimeValue(success.value, defaultCapabilities: ["swiftUIBasic"]) else {
                XCTFail("Expected ViewTree payload")
                return
            }
            XCTAssertEqual(tree.irVersion, 1)
            XCTAssertEqual(tree.root.type, "VStack")
            XCTAssertEqual(tree.root.children.count, 2)
            XCTAssertEqual(tree.root.children.first?.type, "Text")
            XCTAssertEqual(tree.root.children.last?.type, "Button")
            XCTAssertTrue(tree.root.modifiers.contains(where: { $0.type == "padding" }))
            XCTAssertTrue(
                tree.root.children.last?.events.contains(where: {
                    $0.event == "tap" && $0.actionID == "saveTapped"
                }) == true
            )
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }

    func testStateBridgeContextReadsAndWritesStore() {
        let source = """
let state = State()
state.set("title", "Hello")
return state.get("title")
"""
        let engine = Engine()
        var store: [String: RuntimeValue] = [:]
        let context = BridgeScriptContext(
            stateGet: { path in
                store[path] ?? .none
            },
            stateSet: { path, value in
                store[path] = value
            },
            stateBind: { path in
                .dictionary(["$binding": .string(path)])
            }
        )

        let result = BridgeRuntime.withScriptContext(context) {
            engine.compileAndRun(
                .init(
                    source: source,
                    capabilities: [.foundationBasic, .diagnostics, .swiftUIBasic]
                )
            )
        }

        switch result {
        case let .success(success):
            XCTAssertEqual(success.value.stringValue, "Hello")
            XCTAssertEqual(store["title"]?.stringValue, "Hello")
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }
}
