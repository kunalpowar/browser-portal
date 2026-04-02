// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "choose-browser",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ChooseBrowserCore",
            targets: ["ChooseBrowserCore"]
        ),
        .executable(
            name: "ChooseBrowser",
            targets: ["ChooseBrowserApp"]
        ),
    ],
    targets: [
        .target(
            name: "ChooseBrowserCore"
        ),
        .executableTarget(
            name: "ChooseBrowserApp",
            dependencies: ["ChooseBrowserCore"]
        ),
        .testTarget(
            name: "ChooseBrowserCoreTests",
            dependencies: ["ChooseBrowserCore"]
        ),
    ]
)
