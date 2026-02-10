// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftExecEngine",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftExecHost",
            targets: ["SwiftExecHost"]
        ),
        .library(
            name: "SwiftExecFrontend",
            targets: ["SwiftExecFrontend"]
        ),
        .library(
            name: "SwiftExecBytecode",
            targets: ["SwiftExecBytecode"]
        ),
        .library(
            name: "SwiftExecVM",
            targets: ["SwiftExecVM"]
        ),
        .library(
            name: "SwiftExecBridgeRuntime",
            targets: ["SwiftExecBridgeRuntime"]
        ),
        .library(
            name: "SwiftExecSecurity",
            targets: ["SwiftExecSecurity"]
        ),
        .library(
            name: "SwiftExecDiagnostics",
            targets: ["SwiftExecDiagnostics"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftExecSemantic"
        ),
        .target(
            name: "SwiftExecDiagnostics",
            dependencies: [
                "SwiftExecSemantic"
            ]
        ),
        .target(
            name: "SwiftExecBytecode",
            dependencies: [
                "SwiftExecSemantic",
                "SwiftExecDiagnostics"
            ]
        ),
        .target(
            name: "SwiftExecSecurity",
            dependencies: [
                "SwiftExecSemantic"
            ]
        ),
        .target(
            name: "SwiftExecBridgeRuntime",
            dependencies: [
                "SwiftExecSemantic",
                "SwiftExecSecurity",
                "SwiftExecDiagnostics"
            ]
        ),
        .target(
            name: "SwiftExecVM",
            dependencies: [
                "SwiftExecBytecode",
                "SwiftExecSemantic",
                "SwiftExecDiagnostics",
                "SwiftExecBridgeRuntime",
                "SwiftExecSecurity"
            ]
        ),
        .target(
            name: "SwiftExecFrontend",
            dependencies: [
                "SwiftExecBytecode",
                "SwiftExecSemantic",
                "SwiftExecDiagnostics",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftExecHost",
            dependencies: [
                "SwiftExecFrontend",
                "SwiftExecVM",
                "SwiftExecBridgeRuntime",
                "SwiftExecSecurity",
                "SwiftExecDiagnostics"
            ]
        ),
        .executableTarget(
            name: "SwiftExecWrapperGen",
            dependencies: [
                "SwiftExecSemantic",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: "Tools/SwiftExecWrapperGen"
        ),
        .testTarget(
            name: "SwiftExecFrontendTests",
            dependencies: ["SwiftExecFrontend"]
        ),
        .testTarget(
            name: "SwiftExecBytecodeTests",
            dependencies: ["SwiftExecBytecode", "SwiftExecSemantic"]
        ),
        .testTarget(
            name: "SwiftExecVMTests",
            dependencies: ["SwiftExecVM", "SwiftExecBridgeRuntime", "SwiftExecSecurity"]
        ),
        .testTarget(
            name: "SwiftExecIntegrationTests",
            dependencies: ["SwiftExecHost"]
        ),
        .testTarget(
            name: "SwiftExecBenchmarks",
            dependencies: ["SwiftExecHost"]
        )
    ]
)
