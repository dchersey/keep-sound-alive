// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "KeepAlive",
  platforms: [.macOS(.v15)],
  targets: [
    // Pure hold-stack model — no AVFoundation/SwiftUI, so it's fast to unit-test.
    .target(name: "KeepAliveCore", path: "Sources/KeepAliveCore"),
    .executableTarget(
      name: "KeepAlive", dependencies: ["KeepAliveCore"], path: "Sources/KeepAlive"),
    .testTarget(
      name: "KeepAliveCoreTests", dependencies: ["KeepAliveCore"], path: "Tests/KeepAliveCoreTests"),
  ]
)
