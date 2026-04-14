// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "轻图png",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "轻图png", targets: ["轻图png"])
    ],
    targets: [
        .executableTarget(
            name: "轻图png",
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)