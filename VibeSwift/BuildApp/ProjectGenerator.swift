import Foundation

struct ProjectGenerator {
    func generateProject(
        request: BuildAppRequest,
        manifest: VibeAppManifest,
        into rootDirectory: URL
    ) throws -> URL {
        let fm = FileManager.default
        let packageName = manifest.packageName
        let projectDirectory = rootDirectory.appendingPathComponent("\(packageName).vibeapp", isDirectory: true)
        let sourcesDirectory = projectDirectory
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(packageName, isDirectory: true)

        try fm.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)

        let source = canonicalSource(request.source)
        let hasMainAttribute = source.contains("@main")
        let hasContentView = source.contains("struct ContentView")

        if hasMainAttribute {
            try write(source, to: sourcesDirectory.appendingPathComponent("Main.swift"))
        } else {
            try write(appSource(packageName: packageName), to: sourcesDirectory.appendingPathComponent("App.swift"))
            if hasContentView {
                try write(ensureSwiftUIImport(source), to: sourcesDirectory.appendingPathComponent("ContentView.swift"))
            } else {
                try write(
                    fallbackContentView(withSourcePreview: source),
                    to: sourcesDirectory.appendingPathComponent("ContentView.swift")
                )
                try write(commentWrappedSource(source), to: sourcesDirectory.appendingPathComponent("UserSource.swift"))
            }
        }

        try write(packageManifest(packageName: packageName, minimumIOSVersion: manifest.minimumIOSVersion), to: projectDirectory.appendingPathComponent("Package.swift"))
        try write(serializedManifest(manifest), to: projectDirectory.appendingPathComponent("manifest.json"))

        return projectDirectory
    }

    private func canonicalSource(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    private func appSource(packageName: String) -> String {
        """
        import SwiftUI

        @main
        struct \(packageName)App: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """
    }

    private func fallbackContentView(withSourcePreview source: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build exported successfully.")
                            .font(.headline)
                        Text("No native ContentView was detected, so this placeholder was generated.")
                            .font(.subheadline)
                        Divider()
                        Text("Original source:")
                            .font(.headline)
                        Text("\(escaped)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
            }
        }
        """
    }

    private func commentWrappedSource(_ source: String) -> String {
        """
        /*
        Original source exported by VibeSwift Build App mode:

        \(source)
        */
        """
    }

    private func ensureSwiftUIImport(_ source: String) -> String {
        if source.contains("import SwiftUI") {
            return source
        }
        return "import SwiftUI\n\n" + source
    }

    private func packageManifest(packageName: String, minimumIOSVersion: String) -> String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(packageName)",
            platforms: [
                .iOS(.v\(minimumIOSVersion))
            ],
            products: [
                .library(
                    name: "\(packageName)",
                    targets: ["\(packageName)"]
                )
            ],
            targets: [
                .target(
                    name: "\(packageName)"
                )
            ]
        )
        """
    }

    private func serializedManifest(_ manifest: VibeAppManifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        guard var text = String(data: data, encoding: .utf8) else {
            throw BuildAppError.encodingFailed("manifest.json could not be encoded as UTF-8 text.")
        }
        text.append("\n")
        return text
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
