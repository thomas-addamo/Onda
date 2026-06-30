import Foundation
import Metal
import QuartzCore
import simd
import OndaShared
import RenderEngine

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
    private var currentScene: Scene?

    /// Statistiche di frame time della composizione (lette dalla UI).
    private let statsLock = UnfairLock()
    private var stats = FrameTimingStats()

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
        await sources.startSources(from: configuration.sources)
        let scene = configuration.scenes.first { $0.id == configuration.activeSceneID }
            ?? configuration.scenes.first
        stateLock.locked { self.currentScene = scene }

        let link = try DisplayLinkDriver { [weak self] _ in
            self?.renderTick()
        }
        self.displayLink = link
        link.start()
        OndaLog.render.info("StreamSession avviata")
    }

    public func stop() {
        displayLink?.stop()
        displayLink = nil
        sources.stopAll()
    }

    /// Media corrente del frame time di composizione (ms), per la UI.
    public func averageComposeMillis() -> Double {
        statsLock.locked { stats.averageMillis }
    }

    /// Cambia la scena attiva (transizione istantanea per ora).
    public func setActiveScene(_ scene: Scene) {
        stateLock.locked { self.currentScene = scene }
    }

    // MARK: - Render loop

    private func renderTick() {
        let (scene, layer) = stateLock.locked { (currentScene, previewLayer) }
        guard let layer, let drawable = layer.nextDrawable() else { return }
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }

        let startTicks = HighResClock.nowTicks()

        var draws: [Compositor.LayerDraw] = []
        // Trattiene i wrapper CVMetalTexture finche' la GPU non ha finito.
        var retained: [CVMetalTexture] = []

        if let scene {
            for sceneLayer in scene.layers where sceneLayer.isVisible {
                guard let frame = sources.latestFrame(for: sceneLayer.sourceID),
                      let mapped = try? mapper.map(frame.pixelBuffer) else { continue }
                retained.append(mapped.backing)
                let t = sceneLayer.transform
                let rect = SIMD4<Float>(
                    Float(t.rect.origin.x), Float(t.rect.origin.y),
                    Float(t.rect.width), Float(t.rect.height)
                )
                draws.append(Compositor.LayerDraw(
                    texture: mapped.texture, rect: rect, opacity: Float(t.opacity)
                ))
            }
        }

        compositor.compose(layers: draws, into: drawable.texture, commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { _ in
            _ = retained // mantiene vive le texture sorgente fino a fine GPU
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        let elapsed = HighResClock.elapsedMillis(since: startTicks)
        statsLock.locked { stats.add(elapsed) }
    }
}
