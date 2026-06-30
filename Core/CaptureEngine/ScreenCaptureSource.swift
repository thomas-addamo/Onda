import Foundation
import ScreenCaptureKit
import CoreMedia
import OndaShared
import SourceProtocols

/// Sorgente di cattura schermo basata su ScreenCaptureKit.
///
/// I frame arrivano gia' come `CVPixelBuffer` IOSurface-backed dal sistema:
/// vengono inoltrati al consumer senza copie, su una queue dedicata ad alta
/// priorita'. Nessun lavoro pesante nel callback `stream(_:didOutputSampleBuffer:of:)`.
public final class ScreenCaptureSource: NSObject, CaptureSource, SCStreamOutput, @unchecked Sendable {
    public let id = UUID()
    public let kind: CaptureSourceKind = .display
    public private(set) var format: VideoFormat?

    private let display: SCDisplay
    private let configuredFormat: VideoFormat
    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private var isRunning = false

    /// Queue su cui ScreenCaptureKit consegna i sample buffer.
    private let deliveryQueue = DispatchQueue(
        label: "com.onda.capture.screen",
        qos: .userInteractive
    )

    public init(display: SCDisplay, format: VideoFormat = .hd1080p60) {
        self.display = display
        self.configuredFormat = format
        super.init()
    }

    public func setFrameHandler(_ handler: @escaping FrameHandler) {
        deliveryQueue.sync { self.frameHandler = handler }
    }

    public func start() async throws {
        guard !isRunning else { throw CaptureSourceError.alreadyRunning }

        // Filtro: l'intero display, senza escludere finestre.
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = configuredFormat.width
        config.height = configuredFormat.height
        config.pixelFormat = configuredFormat.pixelFormat
        // Intervallo minimo tra frame = budget del frame rate scelto.
        config.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(configuredFormat.frameRate)
        )
        config.queueDepth = 5
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: deliveryQueue)

        do {
            try await stream.startCapture()
        } catch {
            throw CaptureSourceError.configurationFailed("startCapture: \(error.localizedDescription)")
        }

        self.stream = stream
        self.format = configuredFormat
        self.isRunning = true
        OndaLog.capture.info("ScreenCaptureSource avviata su display \(self.display.displayID)")
    }

    public func stop() {
        guard isRunning, let stream else { return }
        isRunning = false
        stream.stopCapture { error in
            if let error {
                OndaLog.capture.error("stopCapture: \(error.localizedDescription)")
            }
        }
        self.stream = nil
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let handler = frameHandler,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        // Scarta i frame "idle" (nessun aggiornamento): ScreenCaptureKit marca
        // lo stato nell'attachment del sample buffer.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            hostTimeTicks: HighResClock.nowTicks()
        )
        handler(frame)
    }

    /// Elenca i display catturabili. Richiede il permesso Screen Recording.
    public static func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays
    }
}
