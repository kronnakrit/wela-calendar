// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "WelaCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "WelaCore", targets: ["WelaCore"])],
  dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")],
  targets: [
    .target(name: "WelaCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
    .testTarget(name: "WelaCoreTests", dependencies: ["WelaCore"]),
  ]
)
