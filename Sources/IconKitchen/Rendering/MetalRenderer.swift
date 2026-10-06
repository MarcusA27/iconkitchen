import Metal
import MetalKit
import AppKit
import simd

/// Mirror of `Uniforms` in the shader. Field order and padding must match.
struct Uniforms {
    var resolution: SIMD2<Float> = .zero
    var lightAngle: Float = -45
    var time: Float = 0
    var colorTop: SIMD4<Float> = .init(0.35, 0.68, 1.0, 1)
    var colorBottom: SIMD4<Float> = .init(0.0, 0.48, 1.0, 1)
    var scale: Float = 0.72
    var cornerCurvature: Float = 5
    var specular: Float = 0.6
    var edgeGlow: Float = 0.5
    var depth: Float = 0.25
    var viewScale: Float = 1
    var viewOffset: SIMD2<Float> = .zero
    var appearance: Float = 0
    var _p0: Float = 0
    var _p1: Float = 0
    var _p2: Float = 0
}

/// Mirror of `ImageUniforms` in the shader.
struct ImageUniforms {
    var resolution: SIMD2<Float> = .zero
    var viewScale: Float = 1
    var baseScale: Float = 0.78
    var viewOffset: SIMD2<Float> = .zero
    var elemOffset: SIMD2<Float> = .zero
    var elemScale: Float = 0.5
    var elemRotation: Float = 0
    var cornerPower: Float = 2.5
    var elemDepth: Float = 0.25
    var lightAngle: Float = -45
    var appearance: Float = 0
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let glassPipeline: MTLRenderPipelineState
    private let imagePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var textureCache: [UUID: (hash: Int, texture: MTLTexture)] = [:]

    /// Set by the SwiftUI layer each time the document changes.
    var store: IconStore?

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: GlassShaderSource.metal, options: nil)
        } catch {
            assertionFailure("Failed to compile Metal library: \(error)")
            return nil
        }

        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            let color = desc.colorAttachments[0]!
            color.pixelFormat = mtkView.colorPixelFormat
            color.isBlendingEnabled = true            // premultiplied "over"
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        guard let glass = pipeline("glass_vertex", "glass_fragment"),
              let image = pipeline("image_vertex", "image_fragment") else {
            assertionFailure("Failed to build pipelines")
            return nil
        }
        glassPipeline = glass
        imagePipeline = image

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let store,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc)
        else { return }

        let res = SIMD2<Float>(Float(view.drawableSize.width),
                               Float(view.drawableSize.height))
        let backing = view.bounds.width > 0
            ? Float(view.drawableSize.width / view.bounds.width) : 1
        let zoom = Float(store.zoom)
        let pan = SIMD2<Float>(Float(store.pan.width) * backing,
                               Float(store.pan.height) * backing)

        let file = store.file
        // Squircle used to mask image elements = the base glass layer's shape.
        let baseScale = Float(file.layers.first { $0.kind == .glassBase }?.scale ?? 0.78)

        for layer in file.layers where layer.isVisible {
            switch layer.kind {
            case .glassBase:
                var u = Uniforms()
                u.resolution = res
                u.lightAngle = Float(file.lightAngle)
                u.colorTop = layer.colorTop.simd
                u.colorBottom = layer.colorBottom.simd
                u.scale = Float(layer.scale)
                u.cornerCurvature = Float(IconMetrics.squircleExponent)
                u.specular = Float(layer.specular)
                u.edgeGlow = Float(layer.edgeGlow)
                u.depth = Float(layer.depth)
                u.viewScale = zoom
                u.viewOffset = pan
                u.appearance = store.appearanceIndex
                enc.setRenderPipelineState(glassPipeline)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            case .image:
                guard let texture = texture(for: layer) else { continue }
                var iu = ImageUniforms()
                iu.resolution = res
                iu.viewScale = zoom
                iu.baseScale = baseScale
                iu.viewOffset = pan
                iu.elemOffset = SIMD2<Float>(Float(layer.offsetX), Float(layer.offsetY))
                iu.elemScale = Float(layer.scale)
                iu.elemRotation = Float(layer.rotation * .pi / 180)
                iu.cornerPower = Float(IconMetrics.squircleExponent * 0.5)
                iu.elemDepth = Float(layer.depth)
                iu.lightAngle = Float(file.lightAngle)
                iu.appearance = store.appearanceIndex
                enc.setRenderPipelineState(imagePipeline)
                enc.setVertexBytes(&iu, length: MemoryLayout<ImageUniforms>.stride, index: 0)
                enc.setFragmentBytes(&iu, length: MemoryLayout<ImageUniforms>.stride, index: 0)
                enc.setFragmentTexture(texture, index: 0)
                enc.setFragmentSamplerState(sampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Texture cache

    private func texture(for layer: IconLayer) -> MTLTexture? {
        guard let data = layer.imageData else { return nil }
        let h = data.hashValue
        if let cached = textureCache[layer.id], cached.hash == h { return cached.texture }
        guard let tex = SVGRasterizer.texture(from: data, device: device) else { return nil }
        textureCache[layer.id] = (h, tex)
        return tex
    }
}

extension RGBAColor {
    var simd: SIMD4<Float> { .init(Float(r), Float(g), Float(b), Float(a)) }
}
