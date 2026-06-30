import Foundation
import AVFoundation
import OndaShared

/// Grafo audio basato su `AVAudioEngine`: uno o piu' canali di input sommati nel
/// mixer principale, con meter di livello per-canale campionati per la UI.
///
/// Realtime-safety: i tap e la lettura dei livelli avvengono fuori dal render
/// block realtime. I livelli sono pubblicati via `UnfairLock` (sezione critica
/// minima) e letti dalla UI a bassa frequenza. Effetti (gate/compressore/EQ)
/// andranno inseriti come nodi con parametri preparati fuori dal thread realtime.
public final class AudioMixer {

    /// Un canale del mixer (es. microfono, sistema, musica).
    public final class Channel: @unchecked Sendable {
        public let id = UUID()
        public let name: String
        let node = AVAudioMixerNode()

        private let lock = UnfairLock()
        private var _level: Float = 0

        init(name: String) { self.name = name }

        /// Livello RMS 0...1 dell'ultimo buffer (per i meter UI).
        public var level: Float { lock.locked { _level } }
        func setLevel(_ value: Float) { lock.locked { _level = value } }

        /// Volume del canale 0...1.
        public func setVolume(_ value: Float) {
            node.outputVolume = max(0, min(1, value))
        }
        public var volume: Float { node.outputVolume }
    }

    private let engine = AVAudioEngine()
    public private(set) var channels: [Channel] = []
    private var isRunning = false

    public init() {}

    /// Avvia il grafo: richiede il permesso microfono e collega l'input al mixer.
    /// In assenza di permesso o dispositivo, lancia: il chiamante deve gestire il
    /// fallimento senza crash (l'app continua col solo video).
    public func start() async throws {
        guard !isRunning else { return }

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw NSError(domain: "Onda.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Permesso microfono negato"])
        }

        let mic = Channel(name: "Microfono")
        engine.attach(mic.node)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        engine.connect(input, to: mic.node, format: inputFormat)
        engine.connect(mic.node, to: engine.mainMixerNode, format: inputFormat)

        installLevelTap(on: mic)

        channels = [mic]
        engine.prepare()
        try engine.start()
        isRunning = true
        OndaLog.audio.info("AudioMixer avviato con \(self.channels.count) canale/i")
    }

    public func stop() {
        guard isRunning else { return }
        channels.forEach { $0.node.removeTap(onBus: 0) }
        engine.stop()
        isRunning = false
    }

    /// Snapshot dei livelli correnti per la UI: (nome, livello 0...1).
    public func levels() -> [(name: String, level: Float)] {
        channels.map { ($0.name, $0.level) }
    }

    public func setMasterVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    /// Installa un tap sul canale per calcolare il livello RMS. Il calcolo gira
    /// sulla queue interna del tap, mai sul main thread.
    private func installLevelTap(on channel: Channel) {
        let format = channel.node.outputFormat(forBus: 0)
        channel.node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak channel] buffer, _ in
            guard let channel, let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            let samples = data[0]
            for i in 0..<frames {
                let s = samples[i]
                sum += s * s
            }
            channel.setLevel((sum / Float(frames)).squareRoot())
        }
    }
}
