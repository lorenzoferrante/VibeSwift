import Foundation
import SwiftExecHost
import SwiftExecSecurity

struct BuildAppRequest: Sendable {
    let source: String
    let appName: String
    let bundleIdentifier: String
    let minimumIOSVersion: String
    let developmentTeam: String
    let buildSettingsOverrides: XcodeBuildSettingsOverrides
    let capabilities: CapabilitySet
    let includeSwiftUI: Bool

    init(
        source: String,
        appName: String,
        bundleIdentifier: String,
        minimumIOSVersion: String = "17.0",
        developmentTeam: String = "YOUR_TEAM_ID",
        buildSettingsOverrides: XcodeBuildSettingsOverrides = .empty,
        capabilities: CapabilitySet = .default,
        includeSwiftUI: Bool = true
    ) {
        self.source = source
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.minimumIOSVersion = minimumIOSVersion
        self.developmentTeam = developmentTeam
        self.buildSettingsOverrides = buildSettingsOverrides
        self.capabilities = capabilities
        self.includeSwiftUI = includeSwiftUI
    }
}
