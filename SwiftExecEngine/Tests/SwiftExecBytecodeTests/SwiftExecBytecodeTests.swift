import SwiftExecBytecode
import XCTest

final class SwiftExecBytecodeTests: XCTestCase {
    func testVarintRoundTrip() throws {
        var bytes: [UInt8] = []
        VarintCodec.encodeSigned(1_234_567, into: &bytes)
        var offset = 0
        let decoded = try VarintCodec.decodeSigned(from: bytes, offset: &offset)
        XCTAssertEqual(decoded, 1_234_567)
    }
}
