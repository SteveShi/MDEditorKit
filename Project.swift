import ProjectDescription

let project = Project(
    name: "MDEditorKit",
    packages: [
        .package(url: "https://github.com/SteveShi/MarkdownView.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MDEditorKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.steveshi.MDEditorKit",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/MDEditorKit/**"],
            dependencies: [
                .package(product: "MarkdownView"),
                .package(product: "MarkdownParser")
            ],
            settings: .settings(
                base: [
                    "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                    "SKIP_INSTALL": "NO",
                    "DEFINES_MODULE": "YES"
                ]
            )
        )
    ]
)
