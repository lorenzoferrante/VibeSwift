import Foundation
import SwiftExecSecurity

struct BuildAppRequest: Sendable {
    let source: String
    let appName: String
    let bundleIdentifier: String
    let minimumIOSVersion: String
    let capabilities: CapabilitySet
    let includeSwiftUI: Bool

    init(
        source: String,
        appName: String,
        bundleIdentifier: String,
        minimumIOSVersion: String = "17.0",
        capabilities: CapabilitySet = .default,
        includeSwiftUI: Bool = true
    ) {
        self.source = source
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.minimumIOSVersion = minimumIOSVersion
        self.capabilities = capabilities
        self.includeSwiftUI = includeSwiftUI
    }
}
