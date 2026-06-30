import AppKit
import Metal
import QuartzCore

/// Vista di preview backed da `CAMetalLayer`: il compositor disegnera' qui il
/// program output al refresh nativo del display, disaccoppiato dal framerate di
/// encode (vedi CLAUDE.md → sincronizzazione col refresh).
///
/// Per ora e' un placeholder visivo; il wiring col Compositor arriva quando
/// colleghiamo la pipeline cattura -> render -> preview.
final class MetalPreviewView: NSView {
    let metalLayer = CAMetalLayer()

    init(device: MTLDevice?) {
        super.init(frame: .zero)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        layer = metalLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func layout() {
        super.layout()
        metalLayer.frame = bounds
        if let scale = window?.backingScaleFactor {
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )
        }
    }
}
