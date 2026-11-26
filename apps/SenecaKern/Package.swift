// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SenecaKern",
    platforms: [.macOS("26.0"), .iOS("18.0")],
    products: [.library(name: "SenecaVerbindung", targets: ["SenecaVerbindung"])],
    targets: [
        .target(name: "SenecaVerbindung", path: "Sources/SenecaVerbindung"),
        .testTarget(name: "PF11", dependencies: ["SenecaVerbindung"], path: "Tests/PF11"),
    ],
    swiftLanguageModes: [.v5]
)
