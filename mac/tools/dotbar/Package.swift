// swift-tools-version:6.0
// dotbar: the top bar as one native app (see odd/tasks/swift-bar.md). The logic lives in DotbarCore so it can be checked
// without a screen; `dotbar` draws it; `dotbar-tests` checks the core (`swift test` needs Xcode, this needs only the
// Command Line Tools): swift run dotbar-tests
import PackageDescription

let package = Package(
    name: "dotbar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "dotbar", targets: ["dotbar"])],
    targets: [
        .target(name: "DotbarCore"),
        .executableTarget(name: "dotbar", dependencies: ["DotbarCore"]),
        .executableTarget(name: "dotbar-tests", dependencies: ["DotbarCore"]),
    ]
)
