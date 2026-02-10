import SwiftExecHost
import XCTest

final class SwiftExecIntegrationTests: XCTestCase {
    func testCompileAndRun() {
        let engine = Engine()
        let result = engine.compileAndRun(.init(source: "let x = 2\nlet y = 3\nprint(x + y)\nreturn x + y"))
        switch result {
        case let .success(value):
            XCTAssertEqual(value.value.int64Value, 5)
            XCTAssertEqual(value.output.last, "5")
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }

    func testFunctionDeclarationAndCall() {
        let source = """
func add(_ lhs: Int, _ rhs: Int) -> Int {
    return lhs + rhs
}
return add(4, 9)
"""
        let engine = Engine()
        let result = engine.compileAndRun(.init(source: source))
        switch result {
        case let .success(value):
            XCTAssertEqual(value.value.int64Value, 13)
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }

    func testWhileLoopAndIfElse() {
        let source = """
var i = 0
var sum = 0
while i < 5 {
    sum = sum + i
    i = i + 1
}
if sum > 5 {
    return sum
} else {
    return 0
}
"""
        let engine = Engine()
        let result = engine.compileAndRun(.init(source: source))
        switch result {
        case let .success(value):
            XCTAssertEqual(value.value.int64Value, 10)
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }

    func testStructCreationAndMemberMutation() {
        let source = """
struct Point {
    var x: Int
    var y: Int
}
var point = Point(2, 3)
point.x = 9
return point.x + point.y
"""
        let engine = Engine()
        let result = engine.compileAndRun(.init(source: source))
        switch result {
        case let .success(value):
            XCTAssertEqual(value.value.int64Value, 12)
        case let .failure(error):
            XCTFail("Unexpected runtime error: \(error.message)")
        }
    }

    func testCapabilityBlocksDisallowedBridgeCall() {
        let source = "return Date.now"
        let engine = Engine()
        let result = engine.compileAndRun(
            .init(
                source: source,
                capabilities: [.foundationBasic, .diagnostics]
            )
        )
        switch result {
        case .success:
            XCTFail("Expected bridge policy failure")
        case let .failure(error):
            XCTAssertTrue(error.message.contains("not allowed"))
        }
    }
}
