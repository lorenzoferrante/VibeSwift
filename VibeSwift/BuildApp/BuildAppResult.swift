import Foundation

struct BuildAppResult: Sendable {
    let packageURL: URL
    let projectDirectoryURL: URL
    let manifest: VibeAppManifest
    let summary: String
    let diagnostics: [String]
    let warnings: [String]
}
