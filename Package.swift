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
        .target(
            name: "MacdaObjC",
            path: "Sources/MacdaObjC"
        ),
        .executableTarget(
            name: "Macda",
            dependencies: ["MacdaObjC"],
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
