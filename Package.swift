// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskPuff",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DeskPuffCore", targets: ["DeskPuffCore"]),
               .executable(name: "DeskPuff", targets: ["DeskPuff"]),
               .executable(name: "FlameLab", targets: ["FlameLab"])],
    targets: [
        .target(name: "DeskPuffCore"),
        .executableTarget(name: "FlameLab", resources: [.copy("Resources")]),
        .executableTarget(name: "DeskPuff", dependencies: ["DeskPuffCore"], resources: [.copy("Resources")]),
        .testTarget(name: "DeskPuffCoreTests", dependencies: ["DeskPuffCore"])
    ]
)
