import Foundation
import AVFoundation
import CoreMedia
import OndaShared
import SourceProtocols

/// Sorgente di cattura webcam / capture card basata su AVFoundation.
///
/// `AVCaptureVideoDataOutput` consegna `CMSampleBuffer` con `CVPixelBuffer`
/// IOSurface-backed su una queue dedicata; inoltriamo senza copie al consumer.
public final class CameraCaptureSource: NSObject, CaptureSource,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    public let id = UUID()
    public let kind: CaptureSourceKind = .camera
    public private(set) var format: VideoFormat?

    private let device: AVCaptureDevice
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var frameHandler: FrameHandler?
    private var isRunning = false

    private let deliveryQueue = DispatchQueue(
        label: "com.onda.capture.camera",
        qos: .userInteractive
    )
    /// Configurazione/avvio della session non vanno sul main thread.
    private let sessionQueue = DispatchQueue(label: "com.onda.capture.camera.session")

    public init(device: AVCaptureDevice) {
        self.device = device
        super.init()
    }

    public func setFrameHandler(_ handler: @escaping FrameHandler) {
        deliveryQueue.sync { self.frameHandler = handler }
    }

    public func start() async throws {
        guard !isRunning else { throw CaptureSourceError.alreadyRunning }

        // Richiesta permesso camera (no-op se gia' concesso).
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { throw CaptureSourceError.permissionDenied }

        try configureSession()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
        isRunning = true
        OndaLog.capture.info("CameraCaptureSource avviata: \(self.device.localizedName)")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionQueue.async { self.session.stopRunning() }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw CaptureSourceError.configurationFailed("input camera non aggiungibile")
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: deliveryQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CaptureSourceError.configurationFailed("output video non aggiungibile")
        }
        session.addOutput(videoOutput)

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        format = VideoFormat(
            width: Int(dims.width),
            height: Int(dims.height),
            pixelFormat: kCVPixelFormatType_32BGRA,
            frameRate: 30
        )
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let handler = frameHandler,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let frame = VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            hostTimeTicks: HighResClock.nowTicks()
        )
        handler(frame)
    }

    /// Elenca le camere disponibili (incluse capture card riconosciute come
    /// dispositivi video esterni).
    public static func availableDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }
}
