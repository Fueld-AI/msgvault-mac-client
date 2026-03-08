// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MsgVaultUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MsgVaultUI",
            path: "MsgVaultMacDesktop/MsgVaultMacDesktop",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        )
    ]
)
