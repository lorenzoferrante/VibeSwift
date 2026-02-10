import SwiftExecBytecode
import SwiftExecSemantic
import SwiftExecVM
import XCTest

final class SwiftExecVMTests: XCTestCase {
    func testSimpleProgramExecutes() throws {
        let constants: [Constant] = [.int64(42)]
        let instructions: [InstructionDescriptor] = [
            .init(opcode: .pushConst, operands: [0]),
            .init(opcode: .returnValue)
        ]
        let functionID: FunctionID = 1
        let program = BytecodeAssembler.assemble(
            descriptors: instructions,
            constants: constants,
            functions: [.init(id: functionID, name: "__entry", entryInstructionIndex: 0, arity: 0, localCount: 0, isEntryPoint: true)],
            symbols: .init()
        )
        let vm = VirtualMachine(program: program)
        let result = try vm.run()
        XCTAssertEqual(result.value.int64Value, 42)
    }
}
