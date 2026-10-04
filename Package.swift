// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Copio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Copio", targets: ["Copio"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Copio",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Copio",
            exclude: [
                "Resources/Info.plist",
                "Resources/Copio.icns",
                "Resources/Copio-icon-preview.png"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
