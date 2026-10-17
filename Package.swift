// swift-tools-version:5.9
import PackageDescription

// ViPiCore (Telex + Pinyin engines) is pure Swift and builds/tests on Linux too.
// The ViPi menu-bar app needs AppKit, so it is only added on macOS.
var products: [Product] = [.library(name: "ViPiCore", targets: ["ViPiCore"])]
var targets: [Target] = [
    .target(name: "ViPiCore"),
    .testTarget(name: "ViPiCoreTests", dependencies: ["ViPiCore"]),
]

#if os(macOS)
products.append(.executable(name: "ViPi", targets: ["ViPi"]))
targets.append(.executableTarget(
    name: "ViPi",
    dependencies: ["ViPiCore"],
    linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("ServiceManagement"),
    ]
))
#endif

let package = Package(
    name: "ViPi",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
