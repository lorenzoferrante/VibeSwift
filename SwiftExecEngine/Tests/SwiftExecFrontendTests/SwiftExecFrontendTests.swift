import SwiftExecFrontend
import XCTest

final class SwiftExecFrontendTests: XCTestCase {
    func testParseAndCompileSimpleSnippet() {
        let output = SwiftBytecodeCompiler.compile(source: "let x = 2\nreturn x")
        XCTAssertNotNil(output.program)
        XCTAssertTrue(output.diagnostics.isEmpty)
    }
}
