// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SamsungTVRemote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SamsungTVRemote", targets: ["SamsungTVRemote"])],
    targets: [
        .executableTarget(name: "SamsungTVRemote")
    ]
)
