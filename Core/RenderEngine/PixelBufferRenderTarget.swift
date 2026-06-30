import Metal
import CoreVideo
import OndaShared

/// Pool di `CVPixelBuffer` IOSurface-backed usati come render target Metal: il
/// compositor disegna nella texture mappata e lo *stesso* `CVPixelBuffer`
/// alimenta l'encoder VideoToolbox, senza copie CPU. I buffer sono riusati dal
/// pool: nessuna allocazione per frame.
public final class PixelBufferRenderTarget {
    private let context: MetalContext
    private let width: Int
    private let height: Int
    private var pool: CVPixelBufferPool?

    public init(context: MetalContext, width: Int, height: Int) throws {
        self.context = context
        self.width = width
        self.height = height
        try makePool()
    }

    /// Un target pronto al disegno: pixel buffer + texture Metal + wrapper da
    /// trattenere finche' la GPU non ha finito.
    public struct Target {
        public let pixelBuffer: CVPixelBuffer
        public let texture: MTLTexture
        public let backing: CVMetalTexture
    }

    private func makePool() throws {
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault, nil, bufferAttrs as CFDictionary, &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw RenderError.pipelineCreationFailed("pool render target: \(status)")
        }
        self.pool = pool
    }

    /// Preleva un buffer dal pool e lo mappa a una texture render-target.
    public func nextTarget() -> Target? {
        guard let pool else { return nil }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        let attrs: [String: Any] = [
            kCVMetalTextureUsage as String: NSNumber(
                value: MTLTextureUsage([.renderTarget, .shaderRead]).rawValue
            )
        ]
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, context.textureCache, pixelBuffer, attrs as CFDictionary,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return Target(pixelBuffer: pixelBuffer, texture: texture, backing: cvTexture)
    }
}
