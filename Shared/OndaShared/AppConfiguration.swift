import Foundation

/// Parametri specifici di una sorgente, sufficienti a ricrearla all'avvio.
/// Enum con valori associati: Codable sintetizzato automaticamente.
public enum SourceConfig: Codable, Sendable, Equatable {
    case display(displayID: UInt32)
    case window(windowID: UInt32)
    case camera(uniqueID: String)
    case text(String, fontSize: Double)
    case image(path: String)
    case testPattern

    public var kind: CaptureSourceKind {
        switch self {
        case .display: return .display
        case .window: return .window
        case .camera: return .camera
        case .text: return .text
        case .image: return .staticImage
        case .testPattern: return .testPattern
        }
    }
}

/// Descrittore persistente di una sorgente: identita' + come ricrearla.
public struct SourceDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var config: SourceConfig

    public init(id: UUID = UUID(), name: String, config: SourceConfig) {
        self.id = id
        self.name = name
        self.config = config
    }

    public var kind: CaptureSourceKind { config.kind }
}

/// Impostazioni di output (encode/registrazione/streaming).
public struct OutputSettings: Codable, Sendable, Equatable {
    public enum Codec: String, Codable, Sendable, CaseIterable {
        case h264, hevc
    }
    public var format: VideoFormat
    public var codec: Codec
    public var bitrate: Int

    public init(format: VideoFormat = .hd1080p60, codec: Codec = .h264, bitrate: Int = 6_000_000) {
        self.format = format
        self.codec = codec
        self.bitrate = bitrate
    }
}

/// Configurazione completa dell'app, serializzata su disco come JSON.
public struct AppConfiguration: Codable, Sendable, Equatable {
    public var sources: [SourceDescriptor]
    public var scenes: [Scene]
    public var activeSceneID: UUID?
    public var output: OutputSettings

    public init(
        sources: [SourceDescriptor] = [],
        scenes: [Scene] = [],
        activeSceneID: UUID? = nil,
        output: OutputSettings = OutputSettings()
    ) {
        self.sources = sources
        self.scenes = scenes
        self.activeSceneID = activeSceneID
        self.output = output
    }

    /// Configurazione di default: una sorgente pattern di test e due scene (a
    /// schermo intero e centrata) per dimostrare lo switching con dissolvenza,
    /// senza permessi di sistema.
    public static var demo: AppConfiguration {
        let source = SourceDescriptor(name: "Pattern di test", config: .testPattern)

        let full = SceneLayer(name: "Pattern", sourceID: source.id, transform: .fullscreen)
        let sceneA = Scene(name: "Scena principale", layers: [full])

        let centered = SceneLayer(
            name: "Pattern (riquadro)",
            sourceID: source.id,
            transform: LayerTransform(rect: CGRect(x: 0.2, y: 0.18, width: 0.6, height: 0.64))
        )
        let sceneB = Scene(name: "Intermezzo", layers: [centered])

        return AppConfiguration(
            sources: [source],
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            output: OutputSettings()
        )
    }
}
