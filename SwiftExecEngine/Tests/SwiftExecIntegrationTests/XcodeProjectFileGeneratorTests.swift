import Foundation
import SwiftExecHost
import XCTest

final class XcodeProjectFileGeneratorTests: XCTestCase {
    func testGeneratedProjectMatchesSnapshot() throws {
        let generator = XcodeProjectFileGenerator()
        let spec = baseSpecification(
            sourceFilePaths: [
                "Sources/GeneratedApp/ContentView.swift",
                "Sources/GeneratedApp/App.swift",
                "Sources/GeneratedApp/UserSource.swift"
            ]
        )

        let generated = generator.generateProjectFile(for: spec)
        let expected = try String(
            contentsOf: fixtureURL(named: "GeneratedBuildAppProject.pbxproj"),
            encoding: .utf8
        )
        XCTAssertEqual(generated, expected)
    }

    func testGeneratedProjectIgnoresInputOrdering() {
        let generator = XcodeProjectFileGenerator()
        let lhs = baseSpecification(
            sourceFilePaths: [
                "Sources/GeneratedApp/App.swift",
                "Sources/GeneratedApp/ContentView.swift",
                "Sources/GeneratedApp/UserSource.swift"
            ]
        )
        let rhs = baseSpecification(
            sourceFilePaths: [
                "Sources/GeneratedApp/UserSource.swift",
                "Sources/GeneratedApp/App.swift",
                "Sources/GeneratedApp/ContentView.swift",
                "Sources/GeneratedApp/App.swift"
            ]
        )

        let first = generator.generateProjectFile(for: lhs)
        let second = generator.generateProjectFile(for: rhs)
        XCTAssertEqual(first, second)
    }

    func testGeneratedProjectCanBeValidatedWithXcodebuild() throws {
#if os(macOS)
        let fm = FileManager.default
        let temporaryRoot = fm.temporaryDirectory
            .appendingPathComponent("xcode-project-validation-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: temporaryRoot)
        }

        let projectName = "ValidationApp"
        let sourceRoot = temporaryRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
        try fm.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        try """
        import SwiftUI

        @main
        struct ValidationApp: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """.write(to: sourceRoot.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Validation")
            }
        }
        """.write(to: sourceRoot.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>CFBundleName</key>
            <string>$(PRODUCT_NAME)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleVersion</key>
            <string>1</string>
        </dict>
        </plist>
        """.write(to: temporaryRoot.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let assetsRoot = temporaryRoot.appendingPathComponent("Assets.xcassets", isDirectory: true)
        try fm.createDirectory(
            at: assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: assetsRoot.appendingPathComponent("AccentColor.colorset", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """.write(to: assetsRoot.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        try """
        {
          "images" : [
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
        """.write(
            to: assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
                .appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
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
        """.write(
            to: assetsRoot.appendingPathComponent("AccentColor.colorset", isDirectory: true)
                .appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )

        let projectFile = XcodeProjectFileGenerator().generateProjectFile(
            for: .init(
                projectName: projectName,
                bundleIdentifier: "com.example.ValidationApp",
                deploymentTarget: "17.0",
                developmentTeam: "YOUR_TEAM_ID",
                infoPlistPath: "Info.plist",
                sourceFilePaths: [
                    "Sources/\(projectName)/App.swift",
                    "Sources/\(projectName)/ContentView.swift"
                ],
                resourceFilePaths: ["Assets.xcassets"]
            )
        )
        let xcodeproj = temporaryRoot.appendingPathComponent("\(projectName).xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try projectFile.write(
            to: xcodeproj.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )

        try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: [
                "xcodebuild",
                "-project", "\(projectName).xcodeproj",
                "-list"
            ],
            currentDirectory: temporaryRoot
        )
        try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: [
                "xcodebuild",
                "-project", "\(projectName).xcodeproj",
                "-target", projectName,
                "-configuration", "Debug",
                "-destination", "generic/platform=iOS Simulator",
                "CODE_SIGNING_ALLOWED=NO",
                "build"
            ],
            currentDirectory: temporaryRoot
        )
#else
        throw XCTSkip("Requires macOS with xcodebuild installed.")
#endif
    }

    private func baseSpecification(sourceFilePaths: [String]) -> XcodeProjectSpecification {
        .init(
            projectName: "GeneratedApp",
            bundleIdentifier: "com.example.GeneratedApp",
            deploymentTarget: "17.0",
            developmentTeam: "YOUR_TEAM_ID",
            infoPlistPath: "Info.plist",
            sourceFilePaths: sourceFilePaths,
            resourceFilePaths: ["Assets.xcassets"],
            buildSettingsOverrides: .init(
                base: ["SWIFT_STRICT_CONCURRENCY": "complete"],
                debug: ["OTHER_SWIFT_FLAGS": "$(inherited) -DDEBUG_EXPORT"],
                release: ["SWIFT_OPTIMIZATION_LEVEL": "-O"]
            )
        )
    }

    private func fixtureURL(named fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

#if os(macOS)
private func runCommand(
    executable: String,
    arguments: [String],
    currentDirectory: URL
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    let output = (String(data: outData, encoding: .utf8) ?? "")
        + (String(data: errData, encoding: .utf8) ?? "")
    XCTAssertEqual(
        process.terminationStatus,
        0,
        "Command failed: \(executable) \(arguments.joined(separator: " "))\n\(output)"
    )
}
#endif
