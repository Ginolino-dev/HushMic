// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "MicMinder",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "MicMinder", targets: ["MicMinder"])
  ],
  targets: [
    .executableTarget(
      name: "MicMinder",
      exclude: ["Resources"],
      linkerSettings: [
        .linkedFramework("ApplicationServices"),
        .linkedFramework("CoreServices"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("ServiceManagement")
      ]
    ),
    .testTarget(name: "MicMinderTests", dependencies: ["MicMinder"])
  ]
)
