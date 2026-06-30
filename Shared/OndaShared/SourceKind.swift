/// Categoria di una sorgente di cattura, per UI, logica di scena e persistenza.
public enum CaptureSourceKind: String, Sendable, Equatable, Codable, CaseIterable {
    case display       // schermo intero (ScreenCaptureKit)
    case window        // singola finestra (ScreenCaptureKit)
    case camera        // webcam / capture card (AVFoundation)
    case staticImage   // immagine o colore fisso
    case text          // overlay testuale renderizzato a texture
    case testPattern   // pattern sintetico di sviluppo (nessun permesso richiesto)

    /// Etichetta leggibile per la UI.
    public var displayName: String {
        switch self {
        case .display: return "Schermo"
        case .window: return "Finestra"
        case .camera: return "Camera"
        case .staticImage: return "Immagine"
        case .text: return "Testo"
        case .testPattern: return "Pattern di test"
        }
    }
}
