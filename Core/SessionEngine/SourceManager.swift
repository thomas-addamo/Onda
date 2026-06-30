import Foundation
import AVFoundation
import ScreenCaptureKit
import OndaShared
import SourceProtocols
import CaptureEngine

/// Crea, avvia e tiene vive le sorgenti di cattura, e conserva l'ultimo frame di
/// ciascuna per la lettura dal render loop.
///
/// I frame arrivano sulle queue di delivery delle sorgenti; il render loop legge
/// l'ultimo frame disponibile. L'accesso e' protetto da un `UnfairLock` con
/// sezione critica minima (semplice scrittura/lettura di un riferimento).
public final class SourceManager: @unchecked Sendable {
    private var sources: [UUID: CaptureSource] = [:]
    private var latestFrames: [UUID: VideoFrame] = [:]
    private let lock = UnfairLock()

    public init() {}

    /// Ultimo frame ricevuto per la sorgente indicata.
    public func latestFrame(for id: UUID) -> VideoFrame? {
        lock.locked { latestFrames[id] }
    }

    /// Crea e avvia le sorgenti dai descrittori. Le creazioni che richiedono
    /// risoluzione di dispositivi (display/camera) sono asincrone; i fallimenti
    /// sono loggati e non interrompono le altre sorgenti.
    public func startSources(from descriptors: [SourceDescriptor]) async {
        for descriptor in descriptors {
            guard let source = await makeSource(descriptor) else {
                OndaLog.capture.error("Sorgente non creata: \(descriptor.name)")
                continue
            }
            let id = descriptor.id
            source.setFrameHandler { [weak self] frame in
                self?.lock.locked { self?.latestFrames[id] = frame }
            }
            lock.locked { sources[id] = source }
            do {
                try await source.start()
            } catch {
                OndaLog.capture.error("Avvio sorgente '\(descriptor.name)' fallito: \(String(describing: error))")
            }
        }
    }

    public func stopAll() {
        let current = lock.locked { Array(sources.values) }
        current.forEach { $0.stop() }
        lock.locked {
            sources.removeAll()
            latestFrames.removeAll()
        }
    }

    // MARK: - Factory

    private func makeSource(_ descriptor: SourceDescriptor) async -> CaptureSource? {
        switch descriptor.config {
        case .testPattern:
            return TestPatternSource(id: descriptor.id)

        case .display(let displayID):
            guard let displays = try? await ScreenCaptureSource.availableDisplays(),
                  let display = displays.first(where: { $0.displayID == displayID }) ?? displays.first else {
                return nil
            }
            return ScreenCaptureSource(display: display)

        case .camera(let uniqueID):
            let devices = CameraCaptureSource.availableDevices()
            guard let device = devices.first(where: { $0.uniqueID == uniqueID }) ?? devices.first else {
                return nil
            }
            return CameraCaptureSource(device: device)

        case .window, .text, .image:
            // Sorgenti non ancora implementate in questo modulo.
            OndaLog.capture.notice("Tipo sorgente non ancora supportato: \(descriptor.kind.displayName)")
            return nil
        }
    }
}
