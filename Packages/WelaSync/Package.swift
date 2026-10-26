// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "WelaSync",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "WelaSync", targets: ["WelaSync"])],
  dependencies: [.package(path: "../WelaCore")],
  targets: [
    .target(name: "WelaSync", dependencies: ["WelaCore"]),
    .testTarget(name: "WelaSyncTests", dependencies: ["WelaSync"]),
  ]
)
