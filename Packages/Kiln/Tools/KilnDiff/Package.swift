// swift-tools-version: 5.9
// KilnDiff: prints the transcript of each input (Kiln.transcript), so two
// builds of Kiln can be compared on the same inputs. See Tools/diff.sh.
import PackageDescription

let package = Package(
    name: "KilnDiff",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "KilnDiff", dependencies: [.product(name: "Kiln", package: "Kiln")])
    ]
)
