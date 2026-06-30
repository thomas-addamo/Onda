import Metal
import CoreVideo
import OndaShared

public enum RenderError: Error {
    case noMetalDevice
    case commandQueueCreationFailed
    case textureCacheCreationFailed
    case pipelineCreationFailed(String)
    case textureMappingFailed
}

/// Risorse Metal condivise dall'intera pipeline di rendering: device, command
/// queue e cache per la conversione zero-copy `CVPixelBuffer` -> `MTLTexture`.
///
/// Creato una volta sola e condiviso; non va ricreato per scena/frame.
public final class MetalContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let textureCache: CVMetalTextureCache

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.commandQueueCreationFailed
        }

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &cache
        )
        guard status == kCVReturnSuccess, let textureCache = cache else {
            throw RenderError.textureCacheCreationFailed
        }

        self.device = device
        self.commandQueue = queue
        self.textureCache = textureCache
        OndaLog.render.info("MetalContext pronto su GPU: \(device.name)")
    }

    /// Svuota periodicamente la cache delle texture (da chiamare fuori dai path
    /// hot, es. ad ogni cambio scena o a bassa frequenza).
    public func flushTextureCache() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }
}
