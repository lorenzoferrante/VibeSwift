import Foundation

public enum VarintCodec {
    public static func encodeUnsigned(_ value: UInt64, into bytes: inout [UInt8]) {
        var value = value
        while true {
            var current = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                current |= 0x80
                bytes.append(current)
            } else {
                bytes.append(current)
                break
            }
        }
    }

    public static func decodeUnsigned(from bytes: [UInt8], offset: inout Int) throws -> UInt64 {
        var shift: UInt64 = 0
        var result: UInt64 = 0

        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 63 {
                throw VarintError.overflow
            }
        }
        throw VarintError.unexpectedEOF
    }

    // ZigZag signed encoding for compact negative numbers.
    public static func encodeSigned(_ value: Int64, into bytes: inout [UInt8]) {
        let zigZag = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        encodeUnsigned(zigZag, into: &bytes)
    }

    public static func decodeSigned(from bytes: [UInt8], offset: inout Int) throws -> Int64 {
        let zigZag = try decodeUnsigned(from: bytes, offset: &offset)
        return Int64(bitPattern: (zigZag >> 1) ^ (UInt64.max * (zigZag & 1)))
    }
}

public enum VarintError: Error, Sendable {
    case overflow
    case unexpectedEOF
}
