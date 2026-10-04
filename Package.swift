// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ROA",
    platforms: [.macOS(.v13)],
    products: [
        // Distinct names are required on the default case-insensitive macOS filesystem.
        .executable(name: "roa-menubar", targets: ["ROAApp"]),
        .executable(name: "roa", targets: ["ROACLI"]),
        .executable(name: "roa-service", targets: ["ROAService"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "ROACore"),
        .target(name: "ROAMac", dependencies: ["ROACore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("SystemConfiguration")]),
        .executableTarget(name: "ROAApp", dependencies: [
            "ROACore", "ROAMac", .product(name: "Sparkle", package: "Sparkle")
        ], linkerSettings: [.linkedFramework("AppKit"),
                           .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "ROACLI", dependencies: ["ROACore", "ROAMac"]),
        .executableTarget(name: "ROAService", dependencies: ["ROACore", "ROAMac"]),
        .testTarget(name: "ROACoreTests", dependencies: ["ROACore"]),
        .testTarget(name: "ROAMacTests", dependencies: ["ROACore", "ROAMac"])
    ]
)
