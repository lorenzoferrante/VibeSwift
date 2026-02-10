import Foundation
import SwiftExecHost

struct VibeAppManifest: Codable, Sendable {
    let version: String
    let formatVersion: Int
    let appName: String
    let packageName: String
    let bundleIdentifier: String
    let minimumIOSVersion: String
    let developmentTeam: String
    let signingStyle: String
    let buildSettingsOverrides: XcodeBuildSettingsOverrides
    let capabilities: [String]
    let sourceHash: String
    let createdAt: Date
}
