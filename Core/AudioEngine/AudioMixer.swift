import Foundation
import AVFoundation
import OndaShared

/// Grafo audio basato su `AVAudioEngine`: somma piu' sorgenti in un mixer
/// principale, con tap per i meter di livello (campionati per la UI, MAI letti
/// in modo bloccante dal render thread realtime).
///
/// NOTA realtime-safety: i tap e la lettura dei livelli avvengono fuori dal
/// render block. Eventuali effetti (gate/compressore/EQ) andranno inseriti come
/// nodi/AudioUnit con parametri preparati fuori dal thread realtime.
public final class AudioMixer {
    private let engine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode

    /// Livello RMS per-canale dell'ultimo buffer del master (0...1),
    /// aggiornato dal tap. Letto dalla UI a bassa frequenza.
    public private(set) var masterLevel: Float = 0

    public init() {
        self.mainMixer = engine.mainMixerNode
    }

    /// Avvia il grafo audio. Va chiamato fuori dai path hot.
    public func start() throws {
        installMasterTap()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            OndaLog.audio.error("AVAudioEngine start fallito: \(error.localizedDescription)")
            throw error
        }
        OndaLog.audio.info("AudioMixer avviato")
    }

    public func stop() {
        mainMixer.removeTap(onBus: 0)
        engine.stop()
    }

    /// Volume master 0...1.
    public func setMasterVolume(_ volume: Float) {
        mainMixer.outputVolume = max(0, min(1, volume))
    }

    /// Installa un tap sul master per calcolare il livello RMS (per i meter).
    /// Il calcolo gira sulla queue interna del tap, non sul main thread.
    private func installMasterTap() {
        let format = mainMixer.outputFormat(forBus: 0)
        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sumSquares: Float = 0
            let samples = channelData[0]
            for i in 0..<frameCount {
                let s = samples[i]
                sumSquares += s * s
            }
            let rms = (sumSquares / Float(frameCount)).squareRoot()
            self.masterLevel = rms
        }
    }
}
