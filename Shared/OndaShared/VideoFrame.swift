import CoreMedia
import CoreVideo

/// Un singolo frame video catturato da una sorgente.
///
/// Incapsula un `CVPixelBuffer` (tipicamente IOSurface-backed, quindi mappabile
/// a texture Metal senza copie) piu' il suo timestamp di presentazione.
///
/// `@unchecked Sendable`: `CVPixelBuffer` e' un tipo CoreFoundation non marcato
/// Sendable, ma il frame viene passato deliberatamente tra la queue di cattura
/// e quella di rendering. La proprieta' del buffer e' a senso unico (chi riceve
/// non muta il buffer originale): trattiamo il trasferimento come sicuro.
public struct VideoFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    /// Tempo di presentazione del frame (timeline della sorgente).
    public let presentationTime: CMTime
    /// Istante di arrivo nel processo, in unita' di `mach_absolute_time`,
    /// usato per misurare la latenza end-to-end.
    public let hostTimeTicks: UInt64

    public init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, hostTimeTicks: UInt64) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.hostTimeTicks = hostTimeTicks
    }

    public var width: Int { CVPixelBufferGetWidth(pixelBuffer) }
    public var height: Int { CVPixelBufferGetHeight(pixelBuffer) }
    public var pixelFormat: OSType { CVPixelBufferGetPixelFormatType(pixelBuffer) }
}
