import Foundation
import CoreGraphics

/// Trasformazione 2D normalizzata di un layer nello spazio della scena.
/// Coordinate in frazioni della dimensione di output (0...1), origine in alto a
/// sinistra. Value type: nessuna pressione su ARC quando attraversa il loop.
public struct LayerTransform: Sendable, Equatable {
    /// Riquadro di destinazione nello spazio normalizzato della scena.
    public var rect: CGRect
    /// Opacita' 0...1 (per dissolvenze e overlay).
    public var opacity: Double
    /// Rotazione in radianti attorno al centro del riquadro.
    public var rotation: Double

    public init(rect: CGRect, opacity: Double = 1.0, rotation: Double = 0) {
        self.rect = rect
        self.opacity = opacity
        self.rotation = rotation
    }

    /// Layer a schermo intero, opaco.
    public static let fullscreen = LayerTransform(
        rect: CGRect(x: 0, y: 0, width: 1, height: 1)
    )
}

/// Un layer della scena: riferisce una sorgente per id e ne descrive la
/// disposizione. Non possiede la sorgente ne' le texture (vivono nell'engine).
public struct SceneLayer: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var sourceID: UUID
    public var transform: LayerTransform
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sourceID: UUID,
        transform: LayerTransform = .fullscreen,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sourceID = sourceID
        self.transform = transform
        self.isVisible = isVisible
    }
}

/// Una scena: lista ordinata di layer (dal fondo verso l'alto) piu' metadati.
/// Lo z-order e' l'ordine dell'array.
public struct Scene: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var layers: [SceneLayer]

    public init(id: UUID = UUID(), name: String, layers: [SceneLayer] = []) {
        self.id = id
        self.name = name
        self.layers = layers
    }
}
