import SwiftExecHost
import XCTest

final class SwiftExecBenchmarks: XCTestCase {
    func testBaselineCompileAndRunPerformance() {
        let engine = Engine()
        measure {
            _ = engine.compileAndRun(.init(source: "let n = 100\nlet m = 42\nreturn n + m"))
        }
    }
}
