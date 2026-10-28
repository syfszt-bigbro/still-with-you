// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "StillWithYou",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "StillWithYou", targets: ["StillWithYouApp"])
  ],
  targets: [
    .target(name: "StillWithYouCore", resources: [.process("Resources")]),
    .target(name: "StillWithYouAssets"),
    .executableTarget(
      name: "StillWithYouApp", dependencies: ["StillWithYouCore", "StillWithYouAssets"],
      resources: [.process("Resources")]),
    .executableTarget(
      name: "CoreChecks", dependencies: ["StillWithYouCore"], path: "Tests/CoreChecks"),
    .executableTarget(
      name: "CharacterAssetChecks", dependencies: ["StillWithYouAssets"],
      path: "Tests/CharacterAssetChecks"),
  ],
  swiftLanguageModes: [.v5])
