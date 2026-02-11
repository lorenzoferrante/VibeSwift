import Foundation

public struct XcodeBuildSettingsOverrides: Codable, Sendable, Equatable {
    public let base: [String: String]
    public let debug: [String: String]
    public let release: [String: String]

    public init(
        base: [String: String] = [:],
        debug: [String: String] = [:],
        release: [String: String] = [:]
    ) {
        self.base = base
        self.debug = debug
        self.release = release
    }

    public static let empty = XcodeBuildSettingsOverrides()
}

public struct XcodeProjectSpecification: Sendable, Equatable {
    public let projectName: String
    public let bundleIdentifier: String
    public let deploymentTarget: String
    public let developmentTeam: String
    public let infoPlistPath: String
    public let sourceFilePaths: [String]
    public let resourceFilePaths: [String]
    public let buildSettingsOverrides: XcodeBuildSettingsOverrides

    public init(
        projectName: String,
        bundleIdentifier: String,
        deploymentTarget: String,
        developmentTeam: String = "YOUR_TEAM_ID",
        infoPlistPath: String = "Info.plist",
        sourceFilePaths: [String],
        resourceFilePaths: [String],
        buildSettingsOverrides: XcodeBuildSettingsOverrides = .empty
    ) {
        self.projectName = projectName
        self.bundleIdentifier = bundleIdentifier
        self.deploymentTarget = deploymentTarget
        self.developmentTeam = developmentTeam
        self.infoPlistPath = infoPlistPath
        self.sourceFilePaths = sourceFilePaths
        self.resourceFilePaths = resourceFilePaths
        self.buildSettingsOverrides = buildSettingsOverrides
    }
}

/// Emits a deterministic minimal iOS app project for generated sources/resources.
/// Object IDs are stable hashes of role + path to keep snapshots repeatable.
public struct XcodeProjectFileGenerator {
    public init() {}

    public func generateProjectFile(for specification: XcodeProjectSpecification) -> String {
        let sourcePaths = normalizedSortedUniquePaths(specification.sourceFilePaths)
        let resourcePaths = normalizedSortedUniquePaths(specification.resourceFilePaths)
        let infoPlistPath = normalizedPath(specification.infoPlistPath)
        let ids = PBXObjectIDs(
            projectName: specification.projectName,
            sourcePaths: sourcePaths,
            resourcePaths: resourcePaths,
            infoPlistPath: infoPlistPath
        )

        let projectDebugSettings: [String: String] = [
            "CLANG_ENABLE_MODULES": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": specification.deploymentTarget,
            "SDKROOT": "iphoneos",
            "SWIFT_VERSION": "5.0"
        ]
        let projectReleaseSettings = projectDebugSettings

        var targetBaseSettings: [String: String] = [
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": infoPlistPath,
            "IPHONEOS_DEPLOYMENT_TARGET": specification.deploymentTarget,
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": specification.bundleIdentifier,
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1,2"
        ]
        let trimmedTeam = specification.developmentTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTeam.isEmpty {
            targetBaseSettings["DEVELOPMENT_TEAM"] = trimmedTeam
        }

        var targetDebugSettings = targetBaseSettings
        targetDebugSettings["ENABLE_TESTABILITY"] = "YES"
        targetDebugSettings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        targetDebugSettings.merge(specification.buildSettingsOverrides.base) { _, new in new }
        targetDebugSettings.merge(specification.buildSettingsOverrides.debug) { _, new in new }

        var targetReleaseSettings = targetBaseSettings
        targetReleaseSettings["SWIFT_COMPILATION_MODE"] = "wholemodule"
        targetReleaseSettings.merge(specification.buildSettingsOverrides.base) { _, new in new }
        targetReleaseSettings.merge(specification.buildSettingsOverrides.release) { _, new in new }

        let sourceBuildFileEntries = sourcePaths.map { path in
            let id = ids.sourceBuildFileIDs[path]!
            let fileReferenceID = ids.sourceFileReferenceIDs[path]!
            return "\t\t\(id) /* \(fileDisplayName(path)) in Sources */ = {isa = PBXBuildFile; fileRef = \(fileReferenceID) /* \(fileDisplayName(path)) */; };"
        }
        let resourceBuildFileEntries = resourcePaths.map { path in
            let id = ids.resourceBuildFileIDs[path]!
            let fileReferenceID = ids.resourceFileReferenceIDs[path]!
            return "\t\t\(id) /* \(fileDisplayName(path)) in Resources */ = {isa = PBXBuildFile; fileRef = \(fileReferenceID) /* \(fileDisplayName(path)) */; };"
        }

        let sourceFileReferenceEntries = sourcePaths.map { path in
            let id = ids.sourceFileReferenceIDs[path]!
            let fileType = fileTypeForReference(path)
            return "\t\t\(id) /* \(fileDisplayName(path)) */ = {isa = PBXFileReference; lastKnownFileType = \(fileType); path = \(pbxQuotedValue(path)); sourceTree = \"<group>\"; };"
        }
        let resourceFileReferenceEntries = resourcePaths.map { path in
            let id = ids.resourceFileReferenceIDs[path]!
            let fileType = fileTypeForReference(path)
            return "\t\t\(id) /* \(fileDisplayName(path)) */ = {isa = PBXFileReference; lastKnownFileType = \(fileType); path = \(pbxQuotedValue(path)); sourceTree = \"<group>\"; };"
        }

        let sourceGroupChildren = sourcePaths.map {
            "\t\t\t\t\(ids.sourceFileReferenceIDs[$0]!) /* \(fileDisplayName($0)) */,"
        }
        var resourceGroupChildren = [
            "\t\t\t\t\(ids.infoPlistFileReferenceID) /* \(fileDisplayName(infoPlistPath)) */,"
        ]
        resourceGroupChildren.append(contentsOf: resourcePaths.map {
            "\t\t\t\t\(ids.resourceFileReferenceIDs[$0]!) /* \(fileDisplayName($0)) */,"
        })

        let sourcesBuildPhaseFiles = sourcePaths.map {
            "\t\t\t\t\(ids.sourceBuildFileIDs[$0]!) /* \(fileDisplayName($0)) in Sources */,"
        }
        let resourcesBuildPhaseFiles = resourcePaths.map {
            "\t\t\t\t\(ids.resourceBuildFileIDs[$0]!) /* \(fileDisplayName($0)) in Resources */,"
        }

        var lines: [String] = []
        lines.append("// !$*UTF8*$!")
        lines.append("{")
        lines.append("\tarchiveVersion = 1;")
        lines.append("\tclasses = {")
        lines.append("\t};")
        lines.append("\tobjectVersion = 56;")
        lines.append("\tobjects = {")
        lines.append("")
        lines.append("/* Begin PBXBuildFile section */")
        lines.append(contentsOf: sourceBuildFileEntries)
        lines.append(contentsOf: resourceBuildFileEntries)
        lines.append("/* End PBXBuildFile section */")
        lines.append("")
        lines.append("/* Begin PBXFileReference section */")
        lines.append("\t\t\(ids.productFileReferenceID) /* \(specification.projectName).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(pbxQuotedValue("\(specification.projectName).app")); sourceTree = BUILT_PRODUCTS_DIR; };")
        lines.append("\t\t\(ids.infoPlistFileReferenceID) /* \(fileDisplayName(infoPlistPath)) */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \(pbxQuotedValue(infoPlistPath)); sourceTree = \"<group>\"; };")
        lines.append(contentsOf: sourceFileReferenceEntries)
        lines.append(contentsOf: resourceFileReferenceEntries)
        lines.append("/* End PBXFileReference section */")
        lines.append("")
        lines.append("/* Begin PBXFrameworksBuildPhase section */")
        lines.append("\t\t\(ids.frameworksBuildPhaseID) /* Frameworks */ = {")
        lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        lines.append("\t\t\tfiles = (")
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
        lines.append("/* End PBXFrameworksBuildPhase section */")
        lines.append("")
        lines.append("/* Begin PBXGroup section */")
        lines.append("\t\t\(ids.mainGroupID) = {")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        lines.append("\t\t\t\t\(ids.sourcesGroupID) /* Sources */,")
        lines.append("\t\t\t\t\(ids.resourcesGroupID) /* Resources */,")
        lines.append("\t\t\t\t\(ids.productsGroupID) /* Products */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
        lines.append("\t\t\(ids.sourcesGroupID) /* Sources */ = {")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        lines.append(contentsOf: sourceGroupChildren)
        lines.append("\t\t\t);")
        lines.append("\t\t\tname = Sources;")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
        lines.append("\t\t\(ids.resourcesGroupID) /* Resources */ = {")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        lines.append(contentsOf: resourceGroupChildren)
        lines.append("\t\t\t);")
        lines.append("\t\t\tname = Resources;")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
        lines.append("\t\t\(ids.productsGroupID) /* Products */ = {")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        lines.append("\t\t\t\t\(ids.productFileReferenceID) /* \(specification.projectName).app */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tname = Products;")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
        lines.append("/* End PBXGroup section */")
        lines.append("")
        lines.append("/* Begin PBXNativeTarget section */")
        lines.append("\t\t\(ids.targetID) /* \(specification.projectName) */ = {")
        lines.append("\t\t\tisa = PBXNativeTarget;")
        lines.append("\t\t\tbuildConfigurationList = \(ids.targetConfigurationListID) /* Build configuration list for PBXNativeTarget \"\(specification.projectName)\" */;")
        lines.append("\t\t\tbuildPhases = (")
        lines.append("\t\t\t\t\(ids.sourcesBuildPhaseID) /* Sources */,")
        lines.append("\t\t\t\t\(ids.frameworksBuildPhaseID) /* Frameworks */,")
        lines.append("\t\t\t\t\(ids.resourcesBuildPhaseID) /* Resources */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tbuildRules = (")
        lines.append("\t\t\t);")
        lines.append("\t\t\tdependencies = (")
        lines.append("\t\t\t);")
        lines.append("\t\t\tname = \(pbxQuotedValue(specification.projectName));")
        lines.append("\t\t\tproductName = \(pbxQuotedValue(specification.projectName));")
        lines.append("\t\t\tproductReference = \(ids.productFileReferenceID) /* \(specification.projectName).app */;")
        lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
        lines.append("\t\t};")
        lines.append("/* End PBXNativeTarget section */")
        lines.append("")
        lines.append("/* Begin PBXProject section */")
        lines.append("\t\t\(ids.projectID) /* Project object */ = {")
        lines.append("\t\t\tisa = PBXProject;")
        lines.append("\t\t\tbuildConfigurationList = \(ids.projectConfigurationListID) /* Build configuration list for PBXProject \"\(specification.projectName)\" */;")
        lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
        lines.append("\t\t\tdevelopmentRegion = en;")
        lines.append("\t\t\thasScannedForEncodings = 0;")
        lines.append("\t\t\tknownRegions = (")
        lines.append("\t\t\t\ten,")
        lines.append("\t\t\t\tBase,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tmainGroup = \(ids.mainGroupID);")
        lines.append("\t\t\tproductRefGroup = \(ids.productsGroupID) /* Products */;")
        lines.append("\t\t\tprojectDirPath = \"\";")
        lines.append("\t\t\tprojectRoot = \"\";")
        lines.append("\t\t\ttargets = (")
        lines.append("\t\t\t\t\(ids.targetID) /* \(specification.projectName) */,")
        lines.append("\t\t\t);")
        lines.append("\t\t};")
        lines.append("/* End PBXProject section */")
        lines.append("")
        lines.append("/* Begin PBXResourcesBuildPhase section */")
        lines.append("\t\t\(ids.resourcesBuildPhaseID) /* Resources */ = {")
        lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        lines.append("\t\t\tfiles = (")
        lines.append(contentsOf: resourcesBuildPhaseFiles)
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
        lines.append("/* End PBXResourcesBuildPhase section */")
        lines.append("")
        lines.append("/* Begin PBXSourcesBuildPhase section */")
        lines.append("\t\t\(ids.sourcesBuildPhaseID) /* Sources */ = {")
        lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        lines.append("\t\t\tfiles = (")
        lines.append(contentsOf: sourcesBuildPhaseFiles)
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
        lines.append("/* End PBXSourcesBuildPhase section */")
        lines.append("")
        lines.append("/* Begin XCBuildConfiguration section */")
        appendBuildConfiguration(
            &lines,
            id: ids.projectDebugConfigurationID,
            name: "Debug",
            settings: projectDebugSettings
        )
        appendBuildConfiguration(
            &lines,
            id: ids.projectReleaseConfigurationID,
            name: "Release",
            settings: projectReleaseSettings
        )
        appendBuildConfiguration(
            &lines,
            id: ids.targetDebugConfigurationID,
            name: "Debug",
            settings: targetDebugSettings
        )
        appendBuildConfiguration(
            &lines,
            id: ids.targetReleaseConfigurationID,
            name: "Release",
            settings: targetReleaseSettings
        )
        lines.append("/* End XCBuildConfiguration section */")
        lines.append("")
        lines.append("/* Begin XCConfigurationList section */")
        lines.append("\t\t\(ids.projectConfigurationListID) /* Build configuration list for PBXProject \"\(specification.projectName)\" */ = {")
        lines.append("\t\t\tisa = XCConfigurationList;")
        lines.append("\t\t\tbuildConfigurations = (")
        lines.append("\t\t\t\t\(ids.projectDebugConfigurationID) /* Debug */,")
        lines.append("\t\t\t\t\(ids.projectReleaseConfigurationID) /* Release */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append("\t\t\tdefaultConfigurationName = Release;")
        lines.append("\t\t};")
        lines.append("\t\t\(ids.targetConfigurationListID) /* Build configuration list for PBXNativeTarget \"\(specification.projectName)\" */ = {")
        lines.append("\t\t\tisa = XCConfigurationList;")
        lines.append("\t\t\tbuildConfigurations = (")
        lines.append("\t\t\t\t\(ids.targetDebugConfigurationID) /* Debug */,")
        lines.append("\t\t\t\t\(ids.targetReleaseConfigurationID) /* Release */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append("\t\t\tdefaultConfigurationName = Release;")
        lines.append("\t\t};")
        lines.append("/* End XCConfigurationList section */")
        lines.append("\t};")
        lines.append("\trootObject = \(ids.projectID) /* Project object */;")
        lines.append("}")

        return lines.joined(separator: "\n") + "\n"
    }
}

private struct PBXObjectIDs {
    let projectID: String
    let mainGroupID: String
    let sourcesGroupID: String
    let resourcesGroupID: String
    let productsGroupID: String
    let productFileReferenceID: String
    let infoPlistFileReferenceID: String
    let targetID: String
    let sourcesBuildPhaseID: String
    let frameworksBuildPhaseID: String
    let resourcesBuildPhaseID: String
    let projectConfigurationListID: String
    let targetConfigurationListID: String
    let projectDebugConfigurationID: String
    let projectReleaseConfigurationID: String
    let targetDebugConfigurationID: String
    let targetReleaseConfigurationID: String
    let sourceFileReferenceIDs: [String: String]
    let sourceBuildFileIDs: [String: String]
    let resourceFileReferenceIDs: [String: String]
    let resourceBuildFileIDs: [String: String]

    init(
        projectName: String,
        sourcePaths: [String],
        resourcePaths: [String],
        infoPlistPath: String
    ) {
        let generator = DeterministicPBXIDGenerator()
        projectID = generator.id(role: "PBXProject", path: "\(projectName)/project")
        mainGroupID = generator.id(role: "PBXGroup", path: "\(projectName)/group/main")
        sourcesGroupID = generator.id(role: "PBXGroup", path: "\(projectName)/group/sources")
        resourcesGroupID = generator.id(role: "PBXGroup", path: "\(projectName)/group/resources")
        productsGroupID = generator.id(role: "PBXGroup", path: "\(projectName)/group/products")
        productFileReferenceID = generator.id(role: "PBXFileReference", path: "\(projectName)/product/\(projectName).app")
        infoPlistFileReferenceID = generator.id(role: "PBXFileReference", path: "\(projectName)/file/\(infoPlistPath)")
        targetID = generator.id(role: "PBXNativeTarget", path: "\(projectName)/target")
        sourcesBuildPhaseID = generator.id(role: "PBXSourcesBuildPhase", path: "\(projectName)/phase/sources")
        frameworksBuildPhaseID = generator.id(role: "PBXFrameworksBuildPhase", path: "\(projectName)/phase/frameworks")
        resourcesBuildPhaseID = generator.id(role: "PBXResourcesBuildPhase", path: "\(projectName)/phase/resources")
        projectConfigurationListID = generator.id(role: "XCConfigurationList", path: "\(projectName)/config/project")
        targetConfigurationListID = generator.id(role: "XCConfigurationList", path: "\(projectName)/config/target")
        projectDebugConfigurationID = generator.id(role: "XCBuildConfiguration", path: "\(projectName)/config/project/debug")
        projectReleaseConfigurationID = generator.id(role: "XCBuildConfiguration", path: "\(projectName)/config/project/release")
        targetDebugConfigurationID = generator.id(role: "XCBuildConfiguration", path: "\(projectName)/config/target/debug")
        targetReleaseConfigurationID = generator.id(role: "XCBuildConfiguration", path: "\(projectName)/config/target/release")

        var sourceFileReferenceIDs: [String: String] = [:]
        var sourceBuildFileIDs: [String: String] = [:]
        for path in sourcePaths {
            sourceFileReferenceIDs[path] = generator.id(role: "PBXFileReference", path: "\(projectName)/source/\(path)")
            sourceBuildFileIDs[path] = generator.id(role: "PBXBuildFile/Sources", path: "\(projectName)/source/\(path)")
        }
        self.sourceFileReferenceIDs = sourceFileReferenceIDs
        self.sourceBuildFileIDs = sourceBuildFileIDs

        var resourceFileReferenceIDs: [String: String] = [:]
        var resourceBuildFileIDs: [String: String] = [:]
        for path in resourcePaths {
            resourceFileReferenceIDs[path] = generator.id(role: "PBXFileReference", path: "\(projectName)/resource/\(path)")
            resourceBuildFileIDs[path] = generator.id(role: "PBXBuildFile/Resources", path: "\(projectName)/resource/\(path)")
        }
        self.resourceFileReferenceIDs = resourceFileReferenceIDs
        self.resourceBuildFileIDs = resourceBuildFileIDs
    }
}

private struct DeterministicPBXIDGenerator {
    func id(role: String, path: String) -> String {
        let seed = "\(role)|\(path)"
        let hashA = fnv1a64(seed, initialHash: 0xcbf29ce484222325, prime: 0x0000_0100_0000_01B3)
        let hashB = fnv1a64(seed, initialHash: 0x84222325cbf29ce4, prime: 0x0000_0100_0000_01B3)
        let combined = paddedHex(hashA) + paddedHex(hashB)
        return String(combined.prefix(24))
    }

    private func fnv1a64(_ value: String, initialHash: UInt64, prime: UInt64) -> UInt64 {
        var hash = initialHash
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    private func paddedHex(_ value: UInt64) -> String {
        let raw = String(value, radix: 16, uppercase: true)
        if raw.count >= 16 {
            return raw
        }
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}

private func appendBuildConfiguration(
    _ lines: inout [String],
    id: String,
    name: String,
    settings: [String: String]
) {
    lines.append("\t\t\(id) /* \(name) */ = {")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for key in settings.keys.sorted() {
        guard let value = settings[key] else { continue }
        lines.append("\t\t\t\t\(key) = \(pbxQuotedValue(value));")
    }
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = \(pbxQuotedValue(name));")
    lines.append("\t\t};")
}

private func normalizedSortedUniquePaths(_ paths: [String]) -> [String] {
    var unique = Set<String>()
    for path in paths {
        let normalized = normalizedPath(path)
        if !normalized.isEmpty {
            unique.insert(normalized)
        }
    }
    return unique.sorted()
}

private func normalizedPath(_ path: String) -> String {
    var normalized = path
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.hasPrefix("./") {
        normalized.removeFirst(2)
    }
    if normalized == "." {
        return ""
    }
    return normalized
}

private func fileDisplayName(_ path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
}

private func fileTypeForReference(_ path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch ext {
    case "swift":
        return "sourcecode.swift"
    case "plist":
        return "text.plist.xml"
    case "xcassets":
        return "folder.assetcatalog"
    case "json":
        return "text.json"
    case "strings":
        return "text.plist.strings"
    default:
        return "text"
    }
}

private func pbxQuotedValue(_ value: String) -> String {
    if value.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil {
        return value
    }
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
