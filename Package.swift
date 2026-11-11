// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoneShellKit",
    platforms: [.iOS(.v15)],
    products: [.library(name: "BoneShellKit", targets: ["BoneShellKit"])],
    targets: [
        .target(name: "BoneShellKit"),
        .testTarget(name: "BoneShellKitTests", dependencies: ["BoneShellKit"])
    ],
    swiftLanguageVersions: [.v5]
)
