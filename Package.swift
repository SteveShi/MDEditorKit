// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MDEditor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MDEditor", targets: ["MDEditor"])
    ],
    dependencies: [
        .package(url: "https://github.com/SteveShi/MarkdownView.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MDEditor",
            dependencies: [
                .product(name: "MarkdownView", package: "MarkdownView"),
                .product(name: "MarkdownParser", package: "MarkdownView"),
            ]
        )
    ]
)
