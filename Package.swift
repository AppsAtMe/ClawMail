// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClawMail",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClawMailCore", targets: ["ClawMailCore"]),
        .library(name: "ClawMailAppLib", targets: ["ClawMailAppLib"]),
        .executable(name: "ClawMailApp", targets: ["ClawMailApp"]),
        .executable(name: "ClawMailCLI", targets: ["ClawMailCLI"]),
        .executable(name: "ClawMailMCP", targets: ["ClawMailMCP"]),
    ],
    dependencies: [
        // Networking
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        // Database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),

        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),

        // HTTP Server (REST API)
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),

        // HTML Parsing
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),

        // Keychain
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        // MARK: - ClawMailCore (shared library)
        .target(
            name: "ClawMailCore",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - ClawMailAppLib (REST API library — routes, middlewares, helpers)
        .target(
            name: "ClawMailAppLib",
            dependencies: [
                "ClawMailCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - ClawMailApp (macOS menu bar app)
        .executableTarget(
            name: "ClawMailApp",
            dependencies: [
                "ClawMailCore",
                "ClawMailAppLib",
            ],
            exclude: [
                "Resources/Info.plist",
                "Resources/ClawMail.entitlements",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - ClawMailCLI (command-line tool)
        .executableTarget(
            name: "ClawMailCLI",
            dependencies: [
                "ClawMailCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - ClawMailMCP (MCP stdio server)
        .executableTarget(
            name: "ClawMailMCP",
            dependencies: [
                "ClawMailCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "ClawMailCoreTests",
            dependencies: ["ClawMailCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ClawMailAppLibTests",
            dependencies: [
                "ClawMailAppLib",
                "ClawMailCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ClawMailAppTests",
            dependencies: [
                "ClawMailApp",
                "ClawMailCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ClawMailIntegrationTests",
            dependencies: ["ClawMailCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
