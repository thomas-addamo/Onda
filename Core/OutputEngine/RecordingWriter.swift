import Foundation
import AVFoundation
import CoreMedia
import OndaShared

public enum RecordingError: Error {
    case cannotCreateWriter(String)
    case notRecording
}

/// Scrive su file i `CMSampleBuffer` gia' compressi dal `VideoEncoder`
/// (passthrough, nessuna ri-codifica) usando `AVAssetWriter`.
///
/// Pensato per la registrazione locale; lo streaming RTMP usera' invece un
/// percorso dedicato nel modulo di output di rete.
public final class RecordingWriter {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var started = false
    private let queue = DispatchQueue(label: "com.onda.output.recording")

    public init() {}

    /// Avvia una registrazione verso `url` (es. .mov). Il primo sample buffer
    /// avvia la sessione con il suo timestamp.
    public func start(to url: URL) throws {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecordingError.cannotCreateWriter(error.localizedDescription)
        }

        // Passthrough: nessun outputSettings, accetta i sample gia' compressi.
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingError.cannotCreateWriter("input video non aggiungibile")
        }
        writer.add(input)

        self.writer = writer
        self.videoInput = input
        self.started = false
        OndaLog.output.info("RecordingWriter pronto: \(url.lastPathComponent)")
    }

    /// Accoda un sample compresso. Avvia la sessione al primo frame.
    public func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self, let writer = self.writer, let input = self.videoInput else { return }

            if !self.started {
                writer.startWriting()
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
                self.started = true
            }

            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            } else {
                OndaLog.output.notice("Input non pronto: frame scartato")
            }
        }
    }

    public func finish(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let writer = self.writer else { completion(); return }
            self.videoInput?.markAsFinished()
            writer.finishWriting { [weak self] in
                self?.writer = nil
                self?.videoInput = nil
                self?.started = false
                completion()
            }
        }
    }
}
