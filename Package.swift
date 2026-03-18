// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MailTrawl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MailTrawl",
            path: "MailTrawl/MailTrawl",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        )
    ]
)
