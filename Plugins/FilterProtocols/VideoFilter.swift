import Metal

/// Effetto/filtro video applicato su GPU a una texture, dentro un command buffer
/// gia' attivo. L'implementazione NON deve fare commit/wait del command buffer
/// (lo fa il compositor) ne' allocare texture per-frame: deve attingere a un
/// pool di texture intermedie fornito dal RenderEngine.
///
/// Ritorna la texture risultato (puo' essere la stessa in input per filtri
/// in-place, o una nuova presa dal pool per filtri che leggono+scrivono).
public protocol VideoFilter: AnyObject {
    /// Nome leggibile per la UI.
    var name: String { get }
    /// Se `false`, il compositor salta il filtro senza schedularlo.
    var isEnabled: Bool { get set }

    func apply(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture
}
