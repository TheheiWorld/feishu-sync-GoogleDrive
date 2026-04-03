// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlyHero",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FlyHero",
            path: "FlyHero",
            exclude: ["Info.plist", "FlyHero.entitlements"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
