import Foundation

public enum Opcode: UInt8, CaseIterable, Sendable {
    case nop = 0x00
    case halt = 0x01

    // Stack/constants
    case pushConst = 0x10
    case pop = 0x11
    case dup = 0x12

    // Locals
    case loadLocal = 0x20
    case storeLocal = 0x21

    // Control flow
    case jump = 0x30
    case jumpIfFalse = 0x31
    case jumpIfTrue = 0x32
    case returnValue = 0x33

    // Calls
    case callUser = 0x40
    case callBridge = 0x41
    case callInit = 0x42

    // Types / members
    case makeStruct = 0x50
    case getField = 0x51
    case setField = 0x52
}
