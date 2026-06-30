// swift-tools-version: 6.0
import PackageDescription

// Onda — software nativo macOS di cattura/compositing/streaming video.
// Struttura modulare a dipendenze a senso unico (vedi CLAUDE.md → Architettura).
//
// Strategia strict concurrency ("dove possibile", da CLAUDE.md):
//  - Moduli di pura logica/protocolli → Swift 6 language mode (strict).
//  - Moduli che incapsulano framework non-Sendable (Metal/AVFoundation/AppKit)
//    → Swift 5 mode per ora, da migrare a Swift 6 incrementalmente.
let package = Package(
    name: "Onda",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Onda", targets: ["OndaApp"]),
        .library(name: "OndaShared", targets: ["OndaShared"]),
        .library(name: "SourceProtocols", targets: ["SourceProtocols"]),
        .library(name: "FilterProtocols", targets: ["FilterProtocols"]),
    ],
    targets: [
        // MARK: - Fondazione (Swift 6 strict)
        .target(
            name: "OndaShared",
            path: "Shared/OndaShared"
        ),
        .target(
            name: "SourceProtocols",
            dependencies: ["OndaShared"],
            path: "Plugins/SourceProtocols"
        ),
        .target(
            name: "FilterProtocols",
            dependencies: ["OndaShared"],
            path: "Plugins/FilterProtocols"
        ),

        // MARK: - Core engines (framework Apple, Swift 5 mode per ora)
        .target(
            name: "CaptureEngine",
            dependencies: ["OndaShared", "SourceProtocols"],
            path: "Core/CaptureEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "RenderEngine",
            dependencies: ["OndaShared", "FilterProtocols"],
            path: "Core/RenderEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AudioEngine",
            dependencies: ["OndaShared"],
            path: "Core/AudioEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "OutputEngine",
            dependencies: ["OndaShared", "RenderEngine"],
            path: "Core/OutputEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - App (AppKit + SwiftUI)
        .executableTarget(
            name: "OndaApp",
            dependencies: [
                "OndaShared",
                "SourceProtocols",
                "FilterProtocols",
                "CaptureEngine",
                "RenderEngine",
                "AudioEngine",
                "OutputEngine",
            ],
            path: "App/OndaApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - Test
        .testTarget(
            name: "OndaUnitTests",
            dependencies: ["OndaShared", "RenderEngine"],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "LatencyBenchmarks",
            dependencies: ["OndaShared", "RenderEngine", "CaptureEngine"],
            path: "Tests/LatencyBenchmarks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
