// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PCLMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PCLMac", targets: ["PCLMac"])
    ],
    targets: [
        .executableTarget(name: "PCLMac"),
        .testTarget(name: "PCLMacTests", dependencies: ["PCLMac"])
    ]
)
