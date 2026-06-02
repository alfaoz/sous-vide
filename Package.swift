// swift-tools-version:6.2
import PackageDescription

// The standalone sous-vide app. The shared chrome + Sous feature + daemon engine
// live in the oxine package (PanelKit / SousKit / SousShared / SousHelperCore);
// this repo is just the app + its helper, branded for sous-vide. Tracking the
// `master` branch means shared edits in oxine flow here on the next resolve.
let package = Package(
    name: "SousVide",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "SousVide", targets: ["SousVide"]),
        .executable(name: "com.sousvide.soushelper", targets: ["SousVideHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/oxineapp/oxine.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "SousVideHelper",
            dependencies: [
                .product(name: "SousShared", package: "oxine"),
                .product(name: "SousHelperCore", package: "oxine")
            ]
        ),
        .executableTarget(
            name: "SousVide",
            dependencies: [
                .product(name: "PanelKit", package: "oxine"),
                .product(name: "SousKit", package: "oxine"),
                .product(name: "SousShared", package: "oxine")
            ]
        )
    ]
)
