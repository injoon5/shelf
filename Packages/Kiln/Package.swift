// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kiln",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "Kiln", targets: ["Kiln"]),
    ],
    targets: [
        .target(
            name: "Kiln",
            dependencies: ["KilnObjC"],
            path: "Sources/Kiln"
        ),
        // The Objective-C runtime half of §1.5's delegate proxies: a proxy
        // object that conforms to a native delegate protocol at run time.
        .target(
            name: "KilnObjC",
            path: "Sources/KilnObjC"
        ),
        .testTarget(
            name: "KilnTests",
            dependencies: ["Kiln"],
            path: "Tests/KilnTests"
        ),
    ]
)
