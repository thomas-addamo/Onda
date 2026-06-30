import Foundation
import Metal
import QuartzCore
import CoreMedia
import simd
import OndaShared
import RenderEngine
import OutputEngine
import AudioEngine

/// Coordinatore della pipeline live: collega sorgenti -> compositor -> preview.
///
/// Possiede le risorse Metal e il render loop (display link). Ad ogni vsync
/// mappa l'ultimo frame di ogni layer della scena attiva a texture, le compone
/// e presenta il risultato sul `CAMetalLayer` della preview. L'encode/output
/// verra' agganciato qui in seguito, sullo stesso percorso.
public final class StreamSession: @unchecked Sendable {
    private let context: MetalContext
    private let compositor: Compositor
    private let mapper: PixelBufferTextureMapper
    private let sources = SourceManager()
    private var displayLink: DisplayLinkDriver?

    private let stateLock = UnfairLock()
    private var previewLayer: CAMetalLayer?
    private var sceneController: SceneController?
    private var outputSettings = OutputSettings()

    /// Statistiche di frame time della composizione (lette dalla UI).
    private let statsLock = UnfairLock()
    private var stats = FrameTimingStats()

    // Registrazione/encode (accesso protetto da stateLock).
    private let audioMixer = AudioMixer()
    private var recording = false
    private var outputTarget: PixelBufferRenderTarget?
    private var encoder: VideoEncoder?
    private var writer: RecordingWriter?
    private var outputFrameIndex: Int64 = 0
    private var lastOutputTicks: UInt64 = 0

    public init() throws {
        self.context = try MetalContext()
        self.compositor = try Compositor(context: context)
        self.mapper = PixelBufferTextureMapper(context: context)
    }

    /// Device Metal condiviso (per configurare il layer della preview).
    public var metalDevice: MTLDevice { context.device }

    /// Collega il layer di preview su cui presentare il program output.
    public func attachPreview(layer: CAMetalLayer) {
        layer.device = context.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        stateLock.locked { self.previewLayer = layer }
    }

    /// Avvia sorgenti, seleziona la scena attiva e fa partire il render loop.
    public func start(configuration: AppConfiguration) async throws {
        stateLock.locked { self.outputSettings = configuration.output }
        await sources.startSources(from: configuration.sources)

        // L'audio non e' bloccante per il video: in caso di permesso negato o
        // assenza di dispositivo, logghiamo e proseguiamo col solo video.
        do {
            try await audioMixer.start()
        } catch {
            OndaLog.audio.error("Audio non avviato: \(String(describing: error))")
        }

        let controller = SceneController(
            scenes: configuration.scenes,
            activeID: configuration.activeSceneID
        )
        stateLock.locked { self.sceneController = controller }

        let link = try DisplayLinkDriver { [weak self] _ in
            self?.renderTick()
        }
        self.displayLink = link
        link.start()
        OndaLog.render.info("StreamSession avviata")
    }

    public func stop() {
        if isRecording { stopRecording() }
        displayLink?.stop()
        displayLink = nil
        sources.stopAll()
        audioMixer.stop()
    }

    /// Livelli audio correnti per i meter UI: (nome, livello 0...1).
    public func audioLevels() -> [(name: String, level: Float)] {
        audioMixer.levels()
    }

    // MARK: - Registrazione

    public var isRecording: Bool { stateLock.locked { recording } }

    /// Avvia la registrazione su file (cartella Filmati) e restituisce l'URL.
    @discardableResult
    public func startRecording() throws -> URL {
        if isRecording { throw VideoEncoderError.notReady }

        let settings = stateLock.locked { outputSettings }
        let target = try PixelBufferRenderTarget(
            context: context,
            width: settings.format.width,
            height: settings.format.height
        )
        let encoder = VideoEncoder(
            format: settings.format,
            codec: settings.codec == .hevc ? .hevc : .h264,
            bitrate: settings.bitrate
        )
        let writer = RecordingWriter()
        let url = Self.makeOutputURL()
        try writer.start(to: url)
        encoder.setEncodedHandler { [weak writer] sample in
            writer?.append(sample)
        }
        try encoder.prepare()

        stateLock.locked {
            self.outputTarget = target
            self.encoder = encoder
            self.writer = writer
            self.outputFrameIndex = 0
            self.lastOutputTicks = 0
            self.recording = true
        }
        OndaLog.output.info("Registrazione avviata: \(url.lastPathComponent)")
        return url
    }

    public func stopRecording() {
        let (enc, wr) = stateLock.locked { () -> (VideoEncoder?, RecordingWriter?) in
            recording = false
            let e = encoder, w = writer
            encoder = nil; writer = nil; outputTarget = nil
            return (e, w)
        }
        enc?.finish()
        wr?.finish {
            OndaLog.output.info("Registrazione conclusa")
        }
    }

    private static func makeOutputURL() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return movies.appendingPathComponent("Onda-\(formatter.string(from: Date())).mov")
    }

    /// Media corrente del frame time di composizione (ms), per la UI.
    public func averageComposeMillis() -> Double {
        statsLock.locked { stats.averageMillis }
    }

    /// Cambia scena con transizione (dissolvenza di default).
    public func switchToScene(id: UUID, kind: TransitionKind = .fade, duration: Double = 0.4) {
        let controller = stateLock.locked { sceneController }
        controller?.switchTo(id, kind: kind, duration: duration)
    }

    /// ID della scena attualmente attiva.
    public func activeSceneID() -> UUID? {
        stateLock.locked { sceneController }?.activeSceneID
    }

    // MARK: - Render loop

    private func renderTick() {
        // Snapshot atomico dello stato condiviso col main thread.
        let controller: SceneController?
        let layer: CAMetalLayer?
        let isRec: Bool
        let target: PixelBufferRenderTarget?
        let enc: VideoEncoder?
        let fps: Int
        (controller, layer, isRec, target, enc, fps) = stateLock.locked {
            (sceneController, previewLayer, recording, outputTarget, encoder, outputSettings.format.frameRate)
        }

        guard let layer, let drawable = layer.nextDrawable() else { return }
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }

        let startTicks = HighResClock.nowTicks()

        // Piano di rendering: una scena, oppure due durante una dissolvenza.
        let passes = controller?.renderPlan() ?? []

        var draws: [Compositor.LayerDraw] = []
        // Trattiene i wrapper CVMetalTexture finche' la GPU non ha finito.
        var retained: [CVMetalTexture] = []

        for pass in passes {
            for sceneLayer in pass.scene.layers where sceneLayer.isVisible {
                guard let frame = sources.latestFrame(for: sceneLayer.sourceID),
                      let mapped = try? mapper.map(frame.pixelBuffer) else { continue }
                retained.append(mapped.backing)
                let t = sceneLayer.transform
                let rect = SIMD4<Float>(
                    Float(t.rect.origin.x), Float(t.rect.origin.y),
                    Float(t.rect.width), Float(t.rect.height)
                )
                draws.append(Compositor.LayerDraw(
                    texture: mapped.texture, rect: rect,
                    opacity: Float(t.opacity) * pass.globalOpacity
                ))
            }
        }

        // Pass di preview sul drawable (refresh nativo del display).
        compositor.compose(layers: draws, into: drawable.texture, commandBuffer: commandBuffer)

        // Pass di output verso l'encoder, con frame pacing al fps configurato.
        var encodePixelBuffer: CVPixelBuffer?
        var encodePTS = CMTime.invalid
        if isRec, let target, let enc, shouldEncodeNow(fps: fps),
           let out = target.nextTarget() {
            compositor.compose(layers: draws, into: out.texture, commandBuffer: commandBuffer)
            retained.append(out.backing)
            encodePixelBuffer = out.pixelBuffer
            let index = stateLock.locked { () -> Int64 in
                let i = outputFrameIndex; outputFrameIndex += 1; return i
            }
            encodePTS = CMTime(value: index, timescale: CMTimeScale(fps))
        }

        commandBuffer.addCompletedHandler { _ in
            _ = retained // mantiene vive le texture sorgente/target fino a fine GPU
            if let pb = encodePixelBuffer, encodePTS.isValid {
                try? enc?.encode(pixelBuffer: pb, pts: encodePTS)
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        let elapsed = HighResClock.elapsedMillis(since: startTicks)
        statsLock.locked { stats.add(elapsed) }
    }

    /// True se e' trascorso almeno il budget del frame rate di output dall'ultimo
    /// frame encodato (disaccoppia l'encode dal refresh del display).
    private func shouldEncodeNow(fps: Int) -> Bool {
        let budgetMillis = 1000.0 / Double(max(1, fps))
        let now = HighResClock.nowTicks()
        return stateLock.locked {
            if lastOutputTicks == 0 || HighResClock.millis(fromTicks: now &- lastOutputTicks) >= budgetMillis {
                lastOutputTicks = now
                return true
            }
            return false
        }
    }
}
