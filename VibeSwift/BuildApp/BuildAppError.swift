import Foundation

enum BuildAppError: LocalizedError {
    case validationFailed([String])
    case packagingFailed(String)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(messages):
            return messages.joined(separator: "\n")
        case let .packagingFailed(message):
            return message
        case let .encodingFailed(message):
            return message
        }
    }
}
