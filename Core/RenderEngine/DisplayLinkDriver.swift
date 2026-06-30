import CoreVideo
import OndaShared

/// Driver del render loop sincronizzato al refresh reale del display tramite
/// `CVDisplayLink`. Il callback gira su un thread di sistema ad alta priorita',
/// MAI sul main thread: l'handler deve essere non bloccante.
///
/// Il framerate di output (encode) e' disaccoppiato da questo refresh: il
/// Compositor decide se/quando emettere un frame all'OutputEngine in base al
/// framerate configurato.
public final class DisplayLinkDriver {
    /// Invocato ad ogni vsync. `hostTime` in tick (`mach_absolute_time`).
    public typealias Tick = (_ hostTimeTicks: UInt64) -> Void

    private var displayLink: CVDisplayLink?
    private let tick: Tick

    public init(tick: @escaping Tick) throws {
        self.tick = tick

        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard status == kCVReturnSuccess, let link else {
            throw RenderError.pipelineCreationFailed("CVDisplayLink non creato")
        }
        self.displayLink = link

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, inNow, _, _, _, context in
            guard let context else { return kCVReturnSuccess }
            let driver = Unmanaged<DisplayLinkDriver>.fromOpaque(context).takeUnretainedValue()
            driver.tick(inNow.pointee.hostTime)
            return kCVReturnSuccess
        }, opaqueSelf)
    }

    public func start() {
        guard let displayLink else { return }
        CVDisplayLinkStart(displayLink)
        OndaLog.render.info("DisplayLink avviato")
    }

    public func stop() {
        guard let displayLink else { return }
        CVDisplayLinkStop(displayLink)
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
