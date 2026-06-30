import AppKit
import Metal
import OndaShared
import SessionEngine

/// Finestra principale in stile "regia": top bar di stato, multiview delle
/// inquadrature, Preview e Program affiancati (studio mode), mixer audio e barra
/// di controllo. Costruita a mano in AppKit con il design system di Onda.
final class MainWindowController: NSWindowController {
    private let device = MTLCreateSystemDefaultDevice()
    private var session: StreamSession?
    private var programPreview: MetalPreviewView?

    private var recordButton: OndaButton?
    private var meters: [NSLevelIndicator] = []
    private var meterTimer: Timer?

    // Indicatori della top bar.
    private var livePill: StatusPill?
    private var recPill: StatusPill?
    private var renderStatLabel: NSTextField?
    private var recStart: Date?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Onda"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = OndaColor.windowBg
        window.minSize = NSSize(width: 1100, height: 700)
        window.center()
        super.init(window: window)
        window.contentView = buildRootView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startSession()
    }

    // MARK: - Sessione live

    private func startSession() {
        guard session == nil, let programPreview else { return }
        do {
            let session = try StreamSession()
            session.attachPreview(layer: programPreview.metalLayer)
            self.session = session

            let config: AppConfiguration
            if let store = try? ConfigurationStore(), let loaded = try? store.loadOrCreateDemo() {
                config = loaded
            } else {
                config = .demo
            }

            Task {
                do { try await session.start(configuration: config) }
                catch { OndaLog.app.error("Avvio sessione fallito: \(String(describing: error))") }
            }
            startStatusUpdates()
        } catch {
            OndaLog.app.error("StreamSession non creata: \(String(describing: error))")
        }
    }

    /// Aggiorna meter audio, tempo di render e pill di stato a 30Hz, leggendo
    /// dati pre-calcolati dalla sessione (mai bloccando il loop critico).
    private func startStatusUpdates() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let session = self.session else { return }

            let levels = session.audioLevels()
            for (index, meter) in self.meters.enumerated() {
                let level = index < levels.count ? levels[index].level : 0
                meter.doubleValue = Double(min(1, level * 3)) * 100
            }

            self.renderStatLabel?.stringValue = String(format: "render %.1f ms", session.averageComposeMillis())

            if session.isRecording, let start = self.recStart {
                let elapsed = Int(Date().timeIntervalSince(start))
                self.recPill?.set(text: String(format: "REC %02d:%02d", elapsed / 60, elapsed % 60), color: OndaColor.accentRed)
            } else {
                self.recPill?.set(text: "STANDBY", color: OndaColor.textTertiary)
            }
        }
    }

    @objc private func toggleRecording(_ sender: OndaButton) {
        guard let session else { return }
        if session.isRecording {
            session.stopRecording()
            recStart = nil
            sender.apply(title: "⦿  Registra")
        } else {
            do {
                let url = try session.startRecording()
                recStart = Date()
                sender.apply(title: "■  Stop")
                OndaLog.app.info("Registro su \(url.path)")
            } catch {
                OndaLog.app.error("Avvio registrazione fallito: \(String(describing: error))")
            }
        }
    }

    // MARK: - Composizione layout

    private func buildRootView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = OndaColor.windowBg.cgColor

        let topBar = buildTopBar()
        let mainArea = NSStackView(views: [buildSidebar(), buildStudioArea(), buildRightPanel()])
        mainArea.orientation = .horizontal
        mainArea.spacing = 10
        mainArea.distribution = .fill
        mainArea.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 6, right: 12)

        let bottomBar = buildBottomBar()

        let stack = NSStackView(views: [topBar, mainArea, bottomBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 56),
            bottomBar.heightAnchor.constraint(equalToConstant: 184),
        ])
        return root
    }

    private func buildTopBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = OndaColor.bar.cgColor

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = OndaColor.stroke.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        // Wordmark con pallino accent (spazio per il semaforo della finestra).
        let mark = trackedLabel("ONDA", size: 15, weight: .bold, color: OndaColor.textPrimary, tracking: 2)
        let scene = trackedLabel("Scena principale", size: 12, weight: .medium, color: OndaColor.textSecondary, tracking: 0.3)

        let left = NSStackView(views: [mark, scene])
        left.orientation = .horizontal
        left.spacing = 16
        left.alignment = .centerY

        let renderStat = NSTextField(labelWithString: "render — ms")
        renderStat.font = OndaFont.mono(11, .medium)
        renderStat.textColor = OndaColor.textTertiary
        self.renderStatLabel = renderStat

        let live = StatusPill(); live.set(text: "OFFLINE", color: OndaColor.textTertiary); self.livePill = live
        let rec = StatusPill(); rec.set(text: "STANDBY", color: OndaColor.textTertiary); self.recPill = rec

        let right = NSStackView(views: [renderStat, rec, live])
        right.orientation = .horizontal
        right.spacing = 12
        right.alignment = .centerY

        [left, right, bar].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        bar.addSubview(left)
        bar.addSubview(right)
        bar.addSubview(divider)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 84),
            left.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])
        return bar
    }

    private func buildSidebar() -> NSView {
        let scenes = PanelView(title: "Scene")
        fillList(scenes.body, items: [
            ("Scena principale", OndaColor.accentRed),
            ("Intermezzo", OndaColor.textTertiary),
            ("Schermata pausa", OndaColor.textTertiary),
        ])
        let sources = PanelView(title: "Sorgenti")
        fillList(sources.body, items: [
            ("Pattern di test", OndaColor.accentGreen),
            ("Schermo intero", OndaColor.textTertiary),
            ("Webcam", OndaColor.textTertiary),
            ("Overlay testo", OndaColor.textTertiary),
        ])

        let stack = NSStackView(views: [scenes, sources])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.widthAnchor.constraint(equalToConstant: 234).isActive = true
        return stack
    }

    private func buildStudioArea() -> NSView {
        let programView = MetalPreviewView(device: device)
        self.programPreview = programView
        let preview = wrapPreview(MetalPreviewView(device: device), title: "PREVIEW", accent: OndaColor.accentGreen)
        let program = wrapPreview(programView, title: "PROGRAM", accent: OndaColor.accentRed)

        let topRow = NSStackView(views: [preview, program])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.distribution = .fillEqually

        let multiview = PanelView(title: "Multiview — Inquadrature")
        let tiles = (1...4).map { previewTile(title: "Inquadratura \($0)") }
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        multiview.body.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: multiview.body.topAnchor),
            row.leadingAnchor.constraint(equalTo: multiview.body.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: multiview.body.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: multiview.body.bottomAnchor),
        ])

        let stack = NSStackView(views: [topRow, multiview])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.distribution = .fill
        topRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        multiview.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return stack
    }

    private func buildRightPanel() -> NSView {
        let transitions = PanelView(title: "Transizioni")
        let cut = OndaButton(title: "Taglio", style: .subtle, target: nil, action: nil)
        let fade = OndaButton(title: "Dissolvenza", style: .filled(OndaColor.accentBlue), target: nil, action: nil)
        let slide = OndaButton(title: "Scorrimento", style: .subtle, target: nil, action: nil)
        let tStack = NSStackView(views: [cut, fade, slide])
        tStack.orientation = .vertical
        tStack.spacing = 8
        tStack.distribution = .fill
        tStack.translatesAutoresizingMaskIntoConstraints = false
        transitions.body.addSubview(tStack)
        pin(tStack, to: transitions.body, top: true)

        let props = PanelView(title: "Proprieta'")
        fillList(props.body, items: [
            ("Posizione", OndaColor.textTertiary),
            ("Scala", OndaColor.textTertiary),
            ("Opacita'", OndaColor.textTertiary),
            ("Filtri", OndaColor.textTertiary),
        ])

        let stack = NSStackView(views: [transitions, props])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.widthAnchor.constraint(equalToConstant: 248).isActive = true
        return stack
    }

    private func buildBottomBar() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = OndaColor.bar.cgColor

        let topDivider = NSView()
        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = OndaColor.stroke.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        let mixer = PanelView(title: "Mixer audio")
        let strips = NSStackView(views: [
            channelStrip(name: "Microfono"),
            channelStrip(name: "Sistema"),
            channelStrip(name: "Musica"),
        ])
        strips.orientation = .horizontal
        strips.spacing = 22
        strips.distribution = .fillEqually
        strips.translatesAutoresizingMaskIntoConstraints = false
        mixer.body.addSubview(strips)
        pin(strips, to: mixer.body)

        let controls = buildControls()

        let stack = NSStackView(views: [mixer, controls])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        container.addSubview(stack)
        container.addSubview(topDivider)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            topDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topDivider.topAnchor.constraint(equalTo: container.topAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),
            controls.widthAnchor.constraint(equalToConstant: 250),
        ])
        return container
    }

    private func buildControls() -> NSView {
        let golive = OndaButton(title: "●  Avvia diretta", style: .filled(OndaColor.accentRed), target: nil, action: nil)
        let record = OndaButton(title: "⦿  Registra", style: .subtle, target: self, action: #selector(toggleRecording(_:)))
        self.recordButton = record
        let camera = OndaButton(title: "Camera virtuale", style: .subtle, target: nil, action: nil)
        let settings = OndaButton(title: "Impostazioni", style: .ghost, target: nil, action: nil)

        let stack = NSStackView(views: [golive, record, camera, settings])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }

    // MARK: - Componenti

    private func wrapPreview(_ preview: MetalPreviewView, title: String, accent: NSColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = OndaColor.tile.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
        container.layer?.borderWidth = 1.5
        container.layer?.masksToBounds = true

        preview.translatesAutoresizingMaskIntoConstraints = false
        let badge = StatusPill()
        badge.set(text: title, color: accent)
        badge.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(preview)
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
        ])
        return container
    }

    private func previewTile(title: String) -> NSView {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.backgroundColor = OndaColor.tile.cgColor
        tile.layer?.cornerRadius = 7
        tile.layer?.borderColor = OndaColor.stroke.cgColor
        tile.layer?.borderWidth = 1

        let label = trackedLabel(title, size: 10, weight: .medium, color: OndaColor.textTertiary)
        label.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            tile.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])
        return tile
    }

    private func channelStrip(name: String) -> NSView {
        let label = trackedLabel(name, size: 11, weight: .semibold, color: OndaColor.textSecondary, tracking: 0.4)

        let meter = NSLevelIndicator()
        meter.levelIndicatorStyle = .continuousCapacity
        meter.minValue = 0
        meter.maxValue = 100
        meter.doubleValue = 0
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.heightAnchor.constraint(equalToConstant: 10).isActive = true
        meters.append(meter)

        let slider = NSSlider(value: 0.8, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.controlSize = .small

        let stack = NSStackView(views: [label, meter, slider])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.distribution = .fill
        return stack
    }

    private func fillList(_ container: NSView, items: [(String, NSColor)]) {
        let rows = items.map { listRow(text: $0.0, dot: $0.1) }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        pin(stack, to: container, top: true)
    }

    private func listRow(text: String, dot color: NSColor) -> NSView {
        let row = NSView()
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = color.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = OndaFont.ui(12.5, .medium)
        label.textColor = OndaColor.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(dot)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 26),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    /// Ancora `view` ai bordi di `container`. Se `top` e' false, lascia libero il
    /// fondo (per contenuti che si dispongono dall'alto).
    private func pin(_ view: NSView, to container: NSView, top: Bool = false) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        if !top {
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
    }
}
