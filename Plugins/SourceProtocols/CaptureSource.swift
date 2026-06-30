import Foundation
import OndaShared

/// Closure invocata per ogni frame prodotto da una sorgente.
///
/// IMPORTANTE: viene chiamata sulla queue di delivery della sorgente (alta
/// priorita'), MAI sul main thread. L'implementazione del consumer deve essere
/// non bloccante e priva di allocazioni evitabili (vedi CLAUDE.md).
public typealias FrameHandler = @Sendable (VideoFrame) -> Void

/// Protocollo che ogni sorgente video deve implementare per inserirsi nella
/// pipeline senza toccare il core di cattura/rendering.
///
/// `start()`/`stop()` non sono path hot: l'uso di `async` qui e' lecito.
/// La consegna dei frame avviene tramite `FrameHandler` su queue dedicata,
/// non tramite polling bloccante ne' `AsyncStream` (che avrebbe overhead per
/// frame non accettabile sui path hot).
public protocol CaptureSource: AnyObject, Sendable {
    var id: UUID { get }
    var kind: CaptureSourceKind { get }
    /// Formato corrente prodotto dalla sorgente, se gia' noto.
    var format: VideoFormat? { get }

    /// Registra il consumer dei frame. Va chiamato prima di `start()`.
    func setFrameHandler(_ handler: @escaping FrameHandler)

    func start() async throws
    func stop()
}

/// Errori comuni delle sorgenti di cattura.
public enum CaptureSourceError: Error, Sendable {
    case permissionDenied
    case sourceUnavailable
    case configurationFailed(String)
    case alreadyRunning
}
