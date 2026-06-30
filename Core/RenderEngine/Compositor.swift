import Metal
import simd
import OndaShared

/// Composita i layer di una scena su una texture di output, su GPU.
///
/// Disegna un quad texturato per ogni layer visibile, in z-order, applicando
/// rettangolo normalizzato e opacita'. La pipeline e' costruita una sola volta;
/// la texture di output e' riusata (nessuna allocazione per frame).
public final class Compositor {
    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState

    public init(context: MetalContext) throws {
        self.context = context
        self.pipelineState = try Compositor.makePipeline(device: context.device)
    }

    /// Uniforms per quad: rettangolo in spazio normalizzato scena (0..1, origine
    /// in alto a sinistra) + opacita'. Layout condiviso con lo shader.
    private struct QuadUniforms {
        var rect: SIMD4<Float>   // x, y, width, height
        var opacity: Float
        var _pad: SIMD3<Float> = .zero
    }

    /// Una texture di un layer con il suo transform, gia' pronta al disegno.
    public struct LayerDraw {
        public let texture: MTLTexture
        public let rect: SIMD4<Float>   // normalizzato 0..1, origine top-left
        public let opacity: Float
        public init(texture: MTLTexture, rect: SIMD4<Float>, opacity: Float) {
            self.texture = texture
            self.rect = rect
            self.opacity = opacity
        }
    }

    /// Compone i layer (dal fondo verso l'alto) nella texture target fornita dal
    /// chiamante (il drawable della preview, oppure una texture IOSurface-backed
    /// per l'encode). Il command buffer NON viene committato qui.
    public func compose(
        layers: [LayerDraw],
        into target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        encoder.setRenderPipelineState(pipelineState)

        for layer in layers {
            var uniforms = QuadUniforms(rect: layer.rect, opacity: layer.opacity)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            encoder.setFragmentTexture(layer.texture, index: 0)
            // Quad = triangle strip di 4 vertici generati nel vertex shader.
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
    }

    // MARK: - Pipeline

    private static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            throw RenderError.pipelineCreationFailed("makeLibrary: \(error.localizedDescription)")
        }

        guard let vertexFn = library.makeFunction(name: "quad_vertex"),
              let fragmentFn = library.makeFunction(name: "quad_fragment") else {
            throw RenderError.pipelineCreationFailed("funzioni shader mancanti")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Alpha blending per overlay/dissolvenze.
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            throw RenderError.pipelineCreationFailed(error.localizedDescription)
        }
    }

    /// Shader MSL: genera un quad da un rettangolo normalizzato e campiona la
    /// texture del layer applicando l'opacita'.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct QuadUniforms {
        float4 rect;    // x, y, width, height (0..1, origine top-left)
        float  opacity;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut quad_vertex(uint vid [[vertex_id]],
                                 constant QuadUniforms& u [[buffer(0)]]) {
        // Quad come triangle strip: (0,0)(1,0)(0,1)(1,1)
        float2 corner = float2(float(vid & 1), float((vid >> 1) & 1));
        float2 normPos = u.rect.xy + corner * u.rect.zw;   // 0..1 top-left
        // 0..1 top-left -> NDC (-1..1, y verso l'alto)
        float2 ndc = float2(normPos.x * 2.0 - 1.0, 1.0 - normPos.y * 2.0);

        VertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = corner;
        return out;
    }

    fragment float4 quad_fragment(VertexOut in [[stage_in]],
                                  constant QuadUniforms& u [[buffer(0)]],
                                  texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = tex.sample(s, in.uv);
        color.a *= u.opacity;
        return color;
    }
    """
}
