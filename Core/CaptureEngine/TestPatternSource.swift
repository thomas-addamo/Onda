import Foundation
import CoreVideo
import CoreMedia
import OndaShared
import SourceProtocols

/// Sorgente sintetica di sviluppo: genera frame con un colore che cambia tinta
/// nel tempo, attingendo a un `CVPixelBufferPool` IOSurface-backed (riuso dei
/// buffer, nessuna alloc per frame). Non richiede permessi di sistema: utile per
/// validare la pipeline render/preview prima di collegare cattura reale.
public final class TestPatternSource: NSObject, CaptureSource, @unchecked Sendable {
    public let id: UUID
    public let kind: CaptureSourceKind = .testPattern
    public private(set) var format: VideoFormat?

    private let configuredFormat: VideoFormat
    private var frameHandler: FrameHandler?
    private var pool: CVPixelBufferPool?
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var frameIndex: UInt64 = 0

    private let queue = DispatchQueue(label: "com.onda.capture.testpattern", qos: .userInteractive)

    public init(id: UUID = UUID(), format: VideoFormat = VideoFormat(
        width: 1280, height: 720,
        pixelFormat: kCVPixelFormatType_32BGRA, frameRate: 60
    )) {
        self.id = id
        self.configuredFormat = format
        super.init()
    }

    public func setFrameHandler(_ handler: @escaping FrameHandler) {
        queue.sync { self.frameHandler = handler }
    }

    public func start() async throws {
        guard !isRunning else { throw CaptureSourceError.alreadyRunning }
        try makePool()
        format = configuredFormat
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1.0 / Double(configuredFormat.frameRate)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.emitFrame() }
        self.timer = timer
        timer.resume()
        OndaLog.capture.info("TestPatternSource avviata")
    }

    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    // MARK: - Pool

    private func makePool() throws {
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: configuredFormat.pixelFormat,
            kCVPixelBufferWidthKey as String: configuredFormat.width,
            kCVPixelBufferHeightKey as String: configuredFormat.height,
            // IOSurface-backed: necessario per la mappatura zero-copy a texture.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw CaptureSourceError.configurationFailed("CVPixelBufferPool: \(status)")
        }
        self.pool = pool
    }

    // MARK: - Generazione frame

    private func emitFrame() {
        guard isRunning, let pool, let handler = frameHandler else { return }

        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let pixelBuffer = buffer else { return }

        fill(pixelBuffer, hueDegrees: Double(frameIndex % 360))
        frameIndex &+= 1

        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(configuredFormat.frameRate))
        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: pts,
            hostTimeTicks: HighResClock.nowTicks()
        )
        handler(frame)
    }

    /// Riempie il buffer BGRA con un colore solido derivato dalla tinta.
    private func fill(_ pixelBuffer: CVPixelBuffer, hueDegrees: Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)

        var pixel = bgraPixel(hueDegrees: hueDegrees)
        let rowBytes = width * 4
        for row in 0..<height {
            let rowPtr = base.advanced(by: row * bytesPerRow)
            memset_pattern4(rowPtr, &pixel, rowBytes)
        }
    }

    /// Converte una tinta (0...360) in un pixel BGRA impacchettato (UInt32).
    private func bgraPixel(hueDegrees: Double) -> UInt32 {
        let (r, g, b) = Self.hsvToRGB(h: hueDegrees, s: 0.7, v: 0.9)
        let rb = UInt32(r * 255), gb = UInt32(g * 255), bb = UInt32(b * 255)
        // Little-endian BGRA in memoria: byte0=B, byte1=G, byte2=R, byte3=A.
        return (0xFF << 24) | (rb << 16) | (gb << 8) | bb
    }

    private static func hsvToRGB(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}
