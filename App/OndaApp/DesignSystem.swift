import AppKit

// Design system di Onda: palette, tipografia e componenti UI riutilizzabili.
// Dark theme "regia": fondo quasi nero, pannelli elevati, accenti netti.

enum OndaColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let windowBg = hex(0x0B0C0E)
    static let bar = hex(0x101216)
    static let panel = hex(0x16181C)
    static let panelElevated = hex(0x1E2128)
    static let tile = hex(0x0A0B0D)

    static let stroke = NSColor.white.withAlphaComponent(0.08)
    static let strokeStrong = NSColor.white.withAlphaComponent(0.16)

    static let textPrimary = NSColor.white.withAlphaComponent(0.92)
    static let textSecondary = NSColor.white.withAlphaComponent(0.55)
    static let textTertiary = NSColor.white.withAlphaComponent(0.34)

    static let accentBlue = hex(0x0A84FF)
    static let accentGreen = hex(0x30D158)
    static let accentRed = hex(0xFF453A)
    static let accentAmber = hex(0xFF9F0A)
}

enum OndaFont {
    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

/// Etichetta con spaziatura tra lettere (per gli header di sezione).
func trackedLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, tracking: CGFloat = 1.2) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: OndaFont.ui(size, weight),
        .foregroundColor: color,
        .kern: tracking,
    ])
    return label
}

/// Pannello con angoli arrotondati, bordo sottile e header opzionale.
final class PanelView: NSView {
    let body = NSView()

    init(title: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = OndaColor.panel.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = OndaColor.stroke.cgColor

        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)

        if let title {
            let header = trackedLabel(title.uppercased(), size: 10, weight: .semibold, color: OndaColor.textTertiary)
            header.translatesAutoresizingMaskIntoConstraints = false
            addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
                body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            ])
        } else {
            body.topAnchor.constraint(equalTo: topAnchor, constant: 12).isActive = true
        }

        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// Pulsante stilizzato (filled / subtle / ghost).
final class OndaButton: NSButton {
    enum Style {
        case filled(NSColor)
        case subtle
        case ghost
    }

    private var style: Style = .subtle

    init(title: String, style: Style, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.style = style
        self.title = ""
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.target = target
        self.action = action
        self.wantsLayer = true
        self.focusRingType = .none
        layer?.cornerRadius = 9
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        apply(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(title: String) {
        let textColor: NSColor
        switch style {
        case .filled:
            textColor = .white
            layer?.backgroundColor = fillColor().cgColor
            layer?.borderWidth = 0
        case .subtle:
            textColor = OndaColor.textPrimary
            layer?.backgroundColor = OndaColor.panelElevated.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = OndaColor.stroke.cgColor
        case .ghost:
            textColor = OndaColor.textSecondary
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = OndaColor.stroke.cgColor
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: OndaFont.ui(13, .semibold),
            .foregroundColor: textColor,
        ])
    }

    private func fillColor() -> NSColor {
        if case let .filled(color) = style { return color }
        return OndaColor.accentBlue
    }
}

/// Indicatore di stato a pillola con pallino colorato (OFFLINE / LIVE / REC ...).
final class StatusPill: NSView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.backgroundColor = OndaColor.panelElevated.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = OndaColor.stroke.cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func set(text: String, color: NSColor) {
        dot.layer?.backgroundColor = color.cgColor
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: OndaFont.ui(11, .semibold),
            .foregroundColor: OndaColor.textSecondary,
            .kern: 0.8,
        ])
    }
}
