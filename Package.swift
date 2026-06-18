// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Macda",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Macda", targets: ["Macda"])
    ],
    targets: [
        .executableTarget(
            name: "Macda",
            path: "Sources/Macda",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
