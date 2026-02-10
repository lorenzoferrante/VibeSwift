import Foundation
import SwiftExecSemantic

#if canImport(SwiftUI)
import SwiftUI

public struct ErasedInterpretedView: View {
    public let anyView: AnyView

    public init(anyView: AnyView) {
        self.anyView = anyView
    }

    public var body: some View {
        anyView
    }
}

public enum SwiftUIBridge {
    public static func asAnyView(_ value: RuntimeValue) -> AnyView? {
        guard case let .native(box) = value, let anyView = box.value as? AnyView else {
            return nil
        }
        return anyView
    }
}
#endif
