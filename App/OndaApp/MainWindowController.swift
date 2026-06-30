import AppKit
import Metal
import OndaShared
import SessionEngine

/// Finestra principale in stile "regia": multiview delle inquadrature, Preview e
/// Program affiancati (studio mode), mixer audio e barra di controllo.
///
/// Layout costruito a mano in AppKit per controllo diretto su refresh e layer.
/// I pannelli secondari (impostazioni, dettaglio mixer) saranno in SwiftUI.
final class MainWindowController: NSWindowController {
    private let device = MTLCreateSystemDefaultDevice()
    private var session: StreamSession?
    private var programPreview: MetalPreviewView?
    private var recordButton: NSButton?
    private var meters: [NSLevelIndicator] = []
    private var meterTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Onda"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1024, height: 640)
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

    /// Crea la sessione live, aggancia la preview Program e avvia con la
    /// configurazione persistita (o la demo col pattern di test).
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
            startMeterUpdates()
        } catch {
            OndaLog.app.error("StreamSession non creata: \(String(describing: error))")
        }
    }

    /// Aggiorna i meter audio a 30Hz leggendo i livelli pre-calcolati dalla
    /// sessione (mai bloccando il loop critico).
    private func startMeterUpdates() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let session = self.session else { return }
            let levels = session.audioLevels()
            for (index, meter) in self.meters.enumerated() {
                let level = index < levels.count ? levels[index].level : 0
                // RMS -> scala 0...100 con un minimo di reattivita' visiva.
                meter.doubleValue = Double(min(1, level * 3)) * 100
            }
        }
    }

    @objc private func toggleRecording(_ sender: NSButton) {
        guard let session else { return }
        if session.isRecording {
            session.stopRecording()
            sender.title = "⦿ Registra"
            sender.contentTintColor = .systemOrange
        } else {
            do {
                let url = try session.startRecording()
                sender.title = "■ Stop"
                sender.contentTintColor = .systemRed
                OndaLog.app.info("Registro su \(url.path)")
            } catch {
                OndaLog.app.error("Avvio registrazione fallito: \(String(describing: error))")
            }
        }
    }

    // MARK: - Composizione layout

    private func buildRootView() -> NSView {
        let root = NSView()

        let mainArea = NSStackView(views: [
            buildSidebar(),
            buildStudioArea(),
            buildRightPanel(),
        ])
        mainArea.orientation = .horizontal
        mainArea.spacing = 8
        mainArea.distribution = .fill
        mainArea.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let bottomBar = buildBottomBar()

        let stack = NSStackView(views: [mainArea, bottomBar])
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
            bottomBar.heightAnchor.constraint(equalToConstant: 160),
        ])
        return root
    }

    /// Sidebar sinistra: elenco scene e sorgenti.
    private func buildSidebar() -> NSView {
        let scenes = titledPanel("SCENE", content: placeholderList([
            "Scena principale", "Intermezzo", "Schermata pausa",
        ]))
        let sources = titledPanel("SORGENTI", content: placeholderList([
            "Schermo intero", "Webcam", "Overlay testo", "Immagine logo",
        ]))

        let stack = NSStackView(views: [scenes, sources])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return stack
    }

    /// Area centrale: Preview + Program affiancati, sotto la multiview.
    private func buildStudioArea() -> NSView {
        let programView = MetalPreviewView(device: device)
        self.programPreview = programView
        let preview = wrapPreview(MetalPreviewView(device: device), title: "PREVIEW", accent: .systemGreen)
        let program = wrapPreview(programView, title: "PROGRAM", accent: .systemRed)

        let topRow = NSStackView(views: [preview, program])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.distribution = .fillEqually

        let multiview = titledPanel("MULTIVIEW — INQUADRATURE", content: buildMultiviewGrid())

        let stack = NSStackView(views: [topRow, multiview])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.distribution = .fill
        topRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return stack
    }

    /// Griglia di anteprime delle inquadrature presenti nella scena.
    private func buildMultiviewGrid() -> NSView {
        let tiles = (1...4).map { index -> NSView in
            previewTile(title: "Inquadratura \(index)")
        }
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        return row
    }

    /// Pannello destro: transizioni e proprieta'.
    private func buildRightPanel() -> NSView {
        let transitions = titledPanel("TRANSIZIONI", content: buildTransitionControls())
        let properties = titledPanel("PROPRIETA'", content: placeholderList([
            "Posizione", "Scala", "Opacita'", "Filtri",
        ]))

        let stack = NSStackView(views: [transitions, properties])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return stack
    }

    private func buildTransitionControls() -> NSView {
        let cut = NSButton(title: "Taglio", target: nil, action: nil)
        let fade = NSButton(title: "Dissolvenza", target: nil, action: nil)
        let slide = NSButton(title: "Scorrimento", target: nil, action: nil)
        [cut, fade, slide].forEach { $0.bezelStyle = .rounded }

        let stack = NSStackView(views: [cut, fade, slide])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        return stack
    }

    /// Barra inferiore: mixer audio a sinistra, controlli di sessione a destra.
    private func buildBottomBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor

        let mixer = titledPanel("MIXER AUDIO", content: buildAudioMixer())
        let controls = buildControlButtons()

        let stack = NSStackView(views: [mixer, controls])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            controls.widthAnchor.constraint(equalToConstant: 220),
        ])
        return bar
    }

    private func buildAudioMixer() -> NSView {
        let channels = ["Microfono", "Sistema", "Musica"].map { channelStrip(name: $0) }
        let stack = NSStackView(views: channels)
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.distribution = .fillEqually
        return stack
    }

    private func channelStrip(name: String) -> NSView {
        let label = makeLabel(name, size: 11, color: .secondaryLabelColor)

        let meter = NSLevelIndicator()
        meter.levelIndicatorStyle = .continuousCapacity
        meter.minValue = 0
        meter.maxValue = 100
        meter.doubleValue = 0
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.heightAnchor.constraint(equalToConstant: 12).isActive = true
        meters.append(meter)

        let slider = NSSlider(value: 0.8, minValue: 0, maxValue: 1, target: nil, action: nil)

        let stack = NSStackView(views: [label, meter, slider])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        return stack
    }

    private func buildControlButtons() -> NSView {
        let golive = bigButton("● Avvia diretta", color: .systemRed)
        let record = bigButton("⦿ Registra", color: .systemOrange)
        record.target = self
        record.action = #selector(toggleRecording(_:))
        self.recordButton = record
        let camera = bigButton("Camera virtuale", color: .systemBlue)
        let settings = bigButton("Impostazioni", color: .systemGray)

        let stack = NSStackView(views: [golive, record, camera, settings])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.distribution = .fillEqually
        return stack
    }

    // MARK: - Helper UI

    private func titledPanel(_ title: String, content: NSView) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.title = ""
        box.titlePosition = .noTitle
        box.cornerRadius = 8
        box.fillColor = NSColor(white: 0.14, alpha: 1)
        box.borderColor = NSColor(white: 0.25, alpha: 1)
        box.borderWidth = 1

        let header = makeLabel(title, size: 10, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 10).isActive = true
        content.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10).isActive = true

        box.contentView = stack
        return box
    }

    private func wrapPreview(_ preview: MetalPreviewView, title: String, accent: NSColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = 6
        container.layer?.borderColor = accent.cgColor
        container.layer?.borderWidth = 2

        preview.translatesAutoresizingMaskIntoConstraints = false

        let badge = makeLabel(title, size: 11, color: accent)
        badge.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(preview)
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
        ])
        return container
    }

    private func previewTile(title: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1).cgColor
        container.layer?.cornerRadius = 4
        container.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        container.layer?.borderWidth = 1

        let label = makeLabel(title, size: 10, color: .secondaryLabelColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])
        return container
    }

    private func placeholderList(_ items: [String]) -> NSView {
        let labels = items.map { makeLabel("•  \($0)", size: 12, color: .labelColor) }
        let stack = NSStackView(views: labels)
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        return stack
    }

    private func bigButton(_ title: String, color: NSColor) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.contentTintColor = color
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        return button
    }

    private func makeLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: .medium)
        label.textColor = color
        return label
    }
}
