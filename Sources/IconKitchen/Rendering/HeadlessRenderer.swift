import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Renders an `IconFile` to a PNG offscreen, no window required. Shares the
/// exact shader the live canvas uses, so it doubles as the export path.
enum HeadlessRenderer {
    enum RenderError: Error { case noDevice, pipeline(Error), texture, readback, encode }

    static func renderPNG(_ file: IconFile, size: Int,
                          appearance: Appearance = .default, to url: URL) throws {
        let apprIdx = Float(Appearance.allCases.firstIndex(of: appearance) ?? 0)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { throw RenderError.noDevice }

        let library: MTLLibrary
        let glassPipeline: MTLRenderPipelineState
        let imagePipeline: MTLRenderPipelineState
        do {
            library = try device.makeLibrary(source: GlassShaderSource.metal, options: nil)
            func makePipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: vertex)
                desc.fragmentFunction = library.makeFunction(name: fragment)
                let color = desc.colorAttachments[0]!
                color.pixelFormat = .rgba8Unorm
                color.isBlendingEnabled = true
                color.rgbBlendOperation = .add
                color.alphaBlendOperation = .add
                color.sourceRGBBlendFactor = .one
                color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: desc)
            }
            glassPipeline = try makePipeline("glass_vertex", "glass_fragment")
            imagePipeline = try makePipeline("image_vertex", "image_fragment")
        } catch { throw RenderError.pipeline(error) }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        let sampler = device.makeSamplerState(descriptor: samplerDesc)!

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: texDesc) else {
            throw RenderError.texture
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: IconMetrics.canvasGray.r,
                                                            green: IconMetrics.canvasGray.g,
                                                            blue: IconMetrics.canvasGray.b, alpha: 1)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass)
        else { throw RenderError.texture }

        let res = SIMD2<Float>(Float(size), Float(size))
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
                u.appearance = apprIdx
                enc.setRenderPipelineState(glassPipeline)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            case .image:
                guard let data = layer.imageData,
                      let texture = SVGRasterizer.texture(from: data, device: device)
                else { continue }
                var iu = ImageUniforms()
                iu.resolution = res
                iu.baseScale = baseScale
                iu.elemOffset = SIMD2<Float>(Float(layer.offsetX), Float(layer.offsetY))
                iu.elemScale = Float(layer.scale)
                iu.elemRotation = Float(layer.rotation * .pi / 180)
                iu.cornerPower = Float(IconMetrics.squircleExponent * 0.5)
                iu.elemDepth = Float(layer.depth)
                iu.lightAngle = Float(file.lightAngle)
                iu.appearance = apprIdx
                enc.setRenderPipelineState(imagePipeline)
                enc.setVertexBytes(&iu, length: MemoryLayout<ImageUniforms>.stride, index: 0)
                enc.setFragmentBytes(&iu, length: MemoryLayout<ImageUniforms>.stride, index: 0)
                enc.setFragmentTexture(texture, index: 0)
                enc.setFragmentSamplerState(sampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        target.getBytes(&pixels, bytesPerRow: bytesPerRow,
                        from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
        else { throw RenderError.readback }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.encode }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.encode }
    }
}
