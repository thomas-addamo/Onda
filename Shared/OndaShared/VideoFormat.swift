import CoreVideo

/// Descrive il formato di un flusso video: dimensioni, pixel format e frame rate.
/// Value type immutabile, sicuro da passare tra thread.
public struct VideoFormat: Sendable, Equatable, Codable {
    public var width: Int
    public var height: Int
    /// OSType del pixel format CoreVideo (es. `kCVPixelFormatType_32BGRA`,
    /// `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`).
    public var pixelFormat: OSType
    /// Frame rate nominale dell'output (fps). La preview puo' girare al refresh
    /// nativo del display; questo valore vincola encode/registrazione.
    public var frameRate: Int

    public init(width: Int, height: Int, pixelFormat: OSType, frameRate: Int) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.frameRate = frameRate
    }

    /// Preset 1080p60 BGRA, formato di lavoro tipico per il compositing su GPU.
    public static let hd1080p60 = VideoFormat(
        width: 1920,
        height: 1080,
        pixelFormat: kCVPixelFormatType_32BGRA,
        frameRate: 60
    )

    /// Preset 1080p30, utile per output/registrazione meno esigenti.
    public static let hd1080p30 = VideoFormat(
        width: 1920,
        height: 1080,
        pixelFormat: kCVPixelFormatType_32BGRA,
        frameRate: 30
    )

    /// Budget di tempo per frame in secondi (1/frameRate).
    public var frameBudget: Double {
        frameRate > 0 ? 1.0 / Double(frameRate) : 0
    }
}
