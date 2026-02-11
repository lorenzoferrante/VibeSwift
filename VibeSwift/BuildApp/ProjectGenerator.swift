import Foundation
import SwiftExecHost

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
        var sourcePaths: [String] = []

        let source = canonicalSource(request.source)
        let hasMainAttribute = source.contains("@main")
        let hasContentView = source.contains("struct ContentView")
        let sourceRootPath = "Sources/\(packageName)"

        if hasMainAttribute {
            let relativePath = "\(sourceRootPath)/Main.swift"
            try write(source, to: projectDirectory.appendingPathComponent(relativePath))
            sourcePaths.append(relativePath)
        } else {
            let appPath = "\(sourceRootPath)/App.swift"
            try write(appSource(packageName: packageName), to: projectDirectory.appendingPathComponent(appPath))
            sourcePaths.append(appPath)

            if hasContentView {
                let contentViewPath = "\(sourceRootPath)/ContentView.swift"
                try write(ensureSwiftUIImport(source), to: projectDirectory.appendingPathComponent(contentViewPath))
                sourcePaths.append(contentViewPath)
            } else {
                let contentViewPath = "\(sourceRootPath)/ContentView.swift"
                try write(
                    fallbackContentView(withSourcePreview: source),
                    to: projectDirectory.appendingPathComponent(contentViewPath)
                )
                sourcePaths.append(contentViewPath)

                let userSourcePath = "\(sourceRootPath)/UserSource.swift"
                try write(commentWrappedSource(source), to: projectDirectory.appendingPathComponent(userSourcePath))
                sourcePaths.append(userSourcePath)
            }
        }

        try write(
            packageManifest(packageName: packageName, minimumIOSVersion: manifest.minimumIOSVersion),
            to: projectDirectory.appendingPathComponent("Package.swift")
        )
        try write(infoPlist(appName: manifest.appName), to: projectDirectory.appendingPathComponent("Info.plist"))
        try writeAssetCatalog(into: projectDirectory)
        try writeXcodeProject(
            packageName: packageName,
            bundleIdentifier: manifest.bundleIdentifier,
            minimumIOSVersion: manifest.minimumIOSVersion,
            developmentTeam: manifest.developmentTeam,
            sourcePaths: sourcePaths,
            buildSettingsOverrides: manifest.buildSettingsOverrides,
            into: projectDirectory
        )
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
                .iOS("\(minimumIOSVersion)")
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

    private func infoPlist(appName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>$(DEVELOPMENT_LANGUAGE)</string>
            <key>CFBundleDisplayName</key>
            <string>\(escapedXML(appName))</string>
            <key>CFBundleExecutable</key>
            <string>$(EXECUTABLE_NAME)</string>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>$(PRODUCT_NAME)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSRequiresIPhoneOS</key>
            <true/>
            <key>UIApplicationSupportsIndirectInputEvents</key>
            <true/>
            <key>UILaunchScreen</key>
            <dict/>
        </dict>
        </plist>
        """
    }

    private func writeAssetCatalog(into projectDirectory: URL) throws {
        let fm = FileManager.default
        let assetsCatalogDirectory = projectDirectory.appendingPathComponent("Assets.xcassets", isDirectory: true)
        let appIconDirectory = assetsCatalogDirectory.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        let accentColorDirectory = assetsCatalogDirectory.appendingPathComponent("AccentColor.colorset", isDirectory: true)

        try fm.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: accentColorDirectory, withIntermediateDirectories: true)

        try write(assetCatalogContentsJSON(), to: assetsCatalogDirectory.appendingPathComponent("Contents.json"))
        try write(appIconContentsJSON(), to: appIconDirectory.appendingPathComponent("Contents.json"))
        try write(accentColorContentsJSON(), to: accentColorDirectory.appendingPathComponent("Contents.json"))
    }

    private func writeXcodeProject(
        packageName: String,
        bundleIdentifier: String,
        minimumIOSVersion: String,
        developmentTeam: String,
        sourcePaths: [String],
        buildSettingsOverrides: XcodeBuildSettingsOverrides,
        into projectDirectory: URL
    ) throws {
        let fm = FileManager.default
        let projectFileGenerator = XcodeProjectFileGenerator()
        let projectSpecification = XcodeProjectSpecification(
            projectName: packageName,
            bundleIdentifier: bundleIdentifier,
            deploymentTarget: minimumIOSVersion,
            developmentTeam: developmentTeam,
            infoPlistPath: "Info.plist",
            sourceFilePaths: sourcePaths,
            resourceFilePaths: ["Assets.xcassets"],
            buildSettingsOverrides: buildSettingsOverrides
        )

        let xcodeprojDirectory = projectDirectory.appendingPathComponent("\(packageName).xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcodeprojDirectory, withIntermediateDirectories: true)
        try write(
            projectFileGenerator.generateProjectFile(for: projectSpecification),
            to: xcodeprojDirectory.appendingPathComponent("project.pbxproj")
        )
    }

    private func assetCatalogContentsJSON() -> String {
        """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
    }

    private func accentColorContentsJSON() -> String {
        """
        {
          "colors" : [
            {
              "color" : {
                "color-space" : "srgb",
                "components" : {
                  "alpha" : "1.000",
                  "blue" : "1.000",
                  "green" : "0.478",
                  "red" : "0.000"
                }
              },
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
    }

    private func appIconContentsJSON() -> String {
        """
        {
          "images" : [
            {
              "idiom" : "iphone",
              "scale" : "2x",
              "size" : "20x20"
            },
            {
              "idiom" : "iphone",
              "scale" : "3x",
              "size" : "20x20"
            },
            {
              "idiom" : "iphone",
              "scale" : "2x",
              "size" : "29x29"
            },
            {
              "idiom" : "iphone",
              "scale" : "3x",
              "size" : "29x29"
            },
            {
              "idiom" : "iphone",
              "scale" : "2x",
              "size" : "40x40"
            },
            {
              "idiom" : "iphone",
              "scale" : "3x",
              "size" : "40x40"
            },
            {
              "idiom" : "iphone",
              "scale" : "2x",
              "size" : "60x60"
            },
            {
              "idiom" : "iphone",
              "scale" : "3x",
              "size" : "60x60"
            },
            {
              "idiom" : "ipad",
              "scale" : "1x",
              "size" : "20x20"
            },
            {
              "idiom" : "ipad",
              "scale" : "2x",
              "size" : "20x20"
            },
            {
              "idiom" : "ipad",
              "scale" : "1x",
              "size" : "29x29"
            },
            {
              "idiom" : "ipad",
              "scale" : "2x",
              "size" : "29x29"
            },
            {
              "idiom" : "ipad",
              "scale" : "1x",
              "size" : "40x40"
            },
            {
              "idiom" : "ipad",
              "scale" : "2x",
              "size" : "40x40"
            },
            {
              "idiom" : "ipad",
              "scale" : "1x",
              "size" : "76x76"
            },
            {
              "idiom" : "ipad",
              "scale" : "2x",
              "size" : "76x76"
            },
            {
              "idiom" : "ipad",
              "scale" : "2x",
              "size" : "83.5x83.5"
            },
            {
              "idiom" : "ios-marketing",
              "scale" : "1x",
              "size" : "1024x1024"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
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

    private func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
