// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SamsungMenuRemote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SamsungMenuRemote", targets: ["SamsungMenuRemote"])],
    targets: [
        .executableTarget(name: "SamsungMenuRemote")
    ]
)
