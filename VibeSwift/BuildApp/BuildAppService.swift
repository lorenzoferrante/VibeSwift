import CryptoKit
import Foundation
import SwiftExecHost
import SwiftExecSecurity

struct BuildAppService {
    private let validator = SourceValidator()
    private let generator = ProjectGenerator()
    private let packager = BundlePackager()
    private let exportCoordinator = ExportCoordinator()
    private let engine = Engine()

    func build(request: BuildAppRequest) throws -> BuildAppResult {
        let validation = validator.validate(request: request, engine: engine)
        guard !validation.hasErrors else {
            throw BuildAppError.validationFailed(validation.diagnostics)
        }

        let packageName = sanitizedTypeName(from: request.appName)
        let manifest = VibeAppManifest(
            version: "1.0",
            formatVersion: 2,
            appName: request.appName,
            packageName: packageName,
            bundleIdentifier: request.bundleIdentifier,
            minimumIOSVersion: request.minimumIOSVersion,
            developmentTeam: request.developmentTeam,
            signingStyle: "Automatic",
            buildSettingsOverrides: request.buildSettingsOverrides,
            capabilities: capabilityNames(request.capabilities),
            sourceHash: sha256(request.source),
            createdAt: Date()
        )

        let fm = FileManager.default
        let rootDirectory = fm.temporaryDirectory
            .appendingPathComponent("vibebuild-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let projectDirectory = try generator.generateProject(
            request: request,
            manifest: manifest,
            into: rootDirectory
        )
        let packageURL: URL
        do {
            packageURL = try packager.package(projectDirectory: projectDirectory, packageName: packageName)
        } catch {
            throw BuildAppError.packagingFailed("Failed to package .vibeapp archive: \(error.localizedDescription)")
        }
        let retainedURL = exportCoordinator.register(packageURL: packageURL)

        let preview = validation.buildPreview
        let summary = """
        Build export complete.
        Package: \(retainedURL.lastPathComponent)
        Xcode project: \(packageName).xcodeproj
        Bytecode bytes: \(preview.bytecodeSize)
        Instructions: \(preview.instructionCount)
        Symbols used: \(preview.usedSymbols.count)
        """

        return BuildAppResult(
            packageURL: retainedURL,
            projectDirectoryURL: projectDirectory,
            manifest: manifest,
            summary: summary,
            diagnostics: validation.diagnostics,
            warnings: validation.warnings
        )
    }

    func cleanup() {
        exportCoordinator.cleanupRetainedPackages()
    }

    private func capabilityNames(_ capabilities: CapabilitySet) -> [String] {
        var names: [String] = []
        if capabilities.contains(.foundationBasic) {
            names.append("foundationBasic")
        }
        if capabilities.contains(.dateFormatting) {
            names.append("dateFormatting")
        }
        if capabilities.contains(.swiftUIBasic) {
            names.append("swiftUIBasic")
        }
        if capabilities.contains(.diagnostics) {
            names.append("diagnostics")
        }
        return names
    }

    private func sha256(_ source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizedTypeName(from appName: String) -> String {
        let cleaned = appName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        if cleaned.isEmpty {
            return "GeneratedApp"
        }
        if cleaned.first?.isNumber == true {
            return "App\(cleaned)"
        }
        return cleaned
    }
}
