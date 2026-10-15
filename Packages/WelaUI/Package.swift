// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "WelaUI",
  platforms: [.macOS(.v14)],
  products: [.library(name: "WelaUI", targets: ["WelaUI"])],
  dependencies: [.package(path: "../WelaCore")],
  targets: [
    .target(name: "WelaUI", dependencies: ["WelaCore"]),
    .testTarget(name: "WelaUITests", dependencies: ["WelaUI"]),
  ]
)
