// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DataGrid",
    platforms: [.iOS(.v18), .macOS(.v15), .visionOS(.v2)],
    products: [
        .library(name: "DataGrid", targets: ["DataGrid"]),
    ],
    targets: [
        .target(name: "DataGrid"),
        .testTarget(name: "DataGridTests", dependencies: ["DataGrid"]),
    ]
)
