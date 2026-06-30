import Metal
import CoreVideo
import OndaShared

/// Mappa un `CVPixelBuffer` IOSurface-backed direttamente a una `MTLTexture`
/// tramite `CVMetalTextureCache`, senza copie CPU ne' allocazioni per frame.
///
/// La `MTLTexture` restituita resta valida finche' il `CVMetalTexture`
/// proprietario e' vivo: il chiamante deve trattenerlo per la durata d'uso.
public struct PixelBufferTextureMapper {
    private let cache: CVMetalTextureCache

    public init(context: MetalContext) {
        self.cache = context.textureCache
    }

    /// Risultato della mappatura: la texture piu' il wrapper CVMetalTexture che
    /// la mantiene in vita (da trattenere finche' la texture e' in uso).
    public struct Mapped {
        public let texture: MTLTexture
        public let backing: CVMetalTexture
    }

    /// Mappa il piano BGRA (single-plane) del pixel buffer a una texture.
    public func map(_ pixelBuffer: CVPixelBuffer) throws -> Mapped {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            throw RenderError.textureMappingFailed
        }

        return Mapped(texture: texture, backing: cvTexture)
    }
}
