import SwiftExecHost
import SwiftExecSecurity
import XCTest

final class SwiftExecBuildPreviewTests: XCTestCase {
    func testBuildPreviewCollectsBridgeSymbols() {
        let engine = Engine()
        let source = """
let name = "vibe"
print(name.uppercased())
return name
"""
        let preview = engine.buildPreview(
            .init(
                source: source,
                capabilities: [.foundationBasic, .diagnostics]
            )
        )

        XCTAssertTrue(preview.vmCompilationSucceeded)
        XCTAssertGreaterThan(preview.bytecodeSize, 0)
        XCTAssertGreaterThan(preview.instructionCount, 0)
        XCTAssertTrue(preview.usedSymbols.contains(where: { $0.name == "Swift.print" }))
        XCTAssertTrue(preview.usedSymbols.contains(where: { $0.name == "Swift.String.uppercased" }))
        XCTAssertTrue(preview.blockedSymbols.isEmpty)
    }

    func testBuildPreviewFlagsBlockedDateSymbolWithoutCapability() {
        let engine = Engine()
        let preview = engine.buildPreview(
            .init(
                source: "return Date.now",
                capabilities: [.foundationBasic, .diagnostics]
            )
        )

        XCTAssertTrue(preview.vmCompilationSucceeded)
        XCTAssertTrue(preview.blockedSymbols.contains(where: { $0.name == "Foundation.Date.now" }))
    }

    func testBuildPreviewReportsCompilationFailure() {
        let engine = Engine()
        let preview = engine.buildPreview(
            .init(
                source: "let x =",
                capabilities: [.foundationBasic, .diagnostics]
            )
        )

        XCTAssertFalse(preview.vmCompilationSucceeded)
        XCTAssertFalse(preview.compilationDiagnostics.isEmpty)
    }
}
