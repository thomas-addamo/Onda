import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import OndaShared

public enum VideoEncoderError: Error {
    case sessionCreationFailed(OSStatus)
    case encodeFailed(OSStatus)
    case notReady
}

/// Encoder hardware H.264/HEVC via VideoToolbox (Media Engine dedicato del chip
/// Apple Silicon). MAI encoding software: vedi vincoli termici in CLAUDE.md.
///
/// Riceve `CVPixelBuffer` (idealmente IOSurface-backed, prodotti dal compositor
/// rendendo su una pixel buffer pool) e consegna `CMSampleBuffer` compressi al
/// muxer/streamer tramite callback.
public final class VideoEncoder {
    public enum Codec {
        case h264
        case hevc

        var cmType: CMVideoCodecType {
            switch self {
            case .h264: return kCMVideoCodecType_H264
            case .hevc: return kCMVideoCodecType_HEVC
            }
        }
    }

    /// Callback con il sample buffer compresso. Chiamata sulla queue interna di
    /// VideoToolbox: non bloccare.
    public typealias EncodedHandler = (CMSampleBuffer) -> Void

    private var session: VTCompressionSession?
    private let format: VideoFormat
    private let codec: Codec
    private let bitrate: Int
    private var encodedHandler: EncodedHandler?

    public init(format: VideoFormat, codec: Codec = .h264, bitrate: Int = 6_000_000) {
        self.format = format
        self.codec = codec
        self.bitrate = bitrate
    }

    public func setEncodedHandler(_ handler: @escaping EncodedHandler) {
        self.encodedHandler = handler
    }

    /// Crea e configura la sessione di compressione hardware.
    public func prepare() throws {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(format.width),
            height: Int32(format.height),
            codecType: codec.cmType,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
            ] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session else {
            throw VideoEncoderError.sessionCreationFailed(status)
        }

        // Configurazione realtime, low-latency.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (format.frameRate * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: format.frameRate as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        OndaLog.output.info("VideoEncoder pronto (\(self.format.width)x\(self.format.height) @\(self.format.frameRate))")
    }

    /// Accoda un frame alla compressione. `pts` e' il presentation timestamp.
    public func encode(pixelBuffer: CVPixelBuffer, pts: CMTime) throws {
        guard let session else { throw VideoEncoderError.notReady }

        let duration = CMTime(value: 1, timescale: CMTimeScale(format.frameRate))
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer else { return }
            self?.encodedHandler?(sampleBuffer)
        }

        if status != noErr {
            throw VideoEncoderError.encodeFailed(status)
        }
    }

    public func finish() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    deinit { finish() }
}
