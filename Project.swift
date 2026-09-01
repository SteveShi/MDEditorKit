import ProjectDescription

let project = Project(
    name: "MDEditorKit",
    packages: [
        .package(url: "https://github.com/Lakr233/MarkdownView.git", from: "4.3.1")
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
