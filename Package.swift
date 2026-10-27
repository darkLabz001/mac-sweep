// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSweep",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacSweep", targets: ["MacSweep"])],
    targets: [.executableTarget(name: "MacSweep")]
)
