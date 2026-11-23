// swift-tools-version: 6.0
// coverage: reads the iOS SDK's SwiftUI interfaces, compares them with Kiln's
// manifest, and writes Packages/Kiln/COVERAGE.md and coverage.json (PLAN.md §1.9).
// A package of its own, with no dependencies, so it never slows the iOS build.
import PackageDescription

let package = Package(
    name: "coverage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CoverageKit"),
        .executableTarget(name: "coverage", dependencies: ["CoverageKit"]),
        .testTarget(
            name: "CoverageKitTests",
            dependencies: ["CoverageKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
