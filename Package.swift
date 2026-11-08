// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StrataBar",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "StrataBar", targets: ["StrataBar"]),
               .executable(name: "StrataBarHelper", targets: ["StrataBarHelper"]),
               .executable(name: "StrataBenchmark", targets: ["StrataBenchmark"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "StrataCore"),
        .target(name: "CSystem", linkerSettings: [.linkedLibrary("proc"), .linkedLibrary("bsm")]),
        .target(name: "StrataInventory", dependencies: ["StrataCore", "CSystem"]),
        .target(name: "StrataHelperInterface"),
        .target(name: "StrataSystem",
                dependencies: ["StrataCore", "CSystem", "StrataInventory", "StrataHelperInterface"]),
        .executableTarget(name: "StrataBar",
                          dependencies: ["StrataCore", "StrataSystem",
                                         .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "StrataBarHelper",
                          dependencies: ["StrataCore", "StrataInventory", "StrataHelperInterface"]),
        .executableTarget(name: "StrataBenchmark", dependencies: ["StrataCore", "StrataSystem"]),
        .executableTarget(name: "StrataQuitFixture", path: "Tests/Fixtures/StrataQuitFixture"),
        .testTarget(name: "StrataCoreTests", dependencies: ["StrataCore"]),
        .testTarget(name: "StrataSystemTests",
                    dependencies: ["StrataCore", "StrataSystem", "StrataInventory", "CSystem",
                                   "StrataQuitFixture"]),
        .testTarget(name: "StrataHelperTests",
                    dependencies: ["StrataBarHelper", "StrataHelperInterface", "StrataInventory",
                                   "StrataSystem", "StrataCore"]),
        .testTarget(name: "StrataAppTests", dependencies: ["StrataBar", "StrataCore", "StrataSystem"])
    ]
)
