import Metal
import MetalKit
import AppKit

/// Rasterizes SVG/PNG bytes into a square RGBA Metal texture (aspect-fit,
/// centered, transparent padding). Shared by the live and headless renderers.
enum SVGRasterizer {
    static func texture(from data: Data, device: MTLDevice, dim: Int = 1024) -> MTLTexture? {
        guard let image = NSImage(data: data), image.size.width > 0 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: dim, pixelsHigh: dim,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: dim, height: dim)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: dim, height: dim).fill()
        let isz = image.size
        let s = min(CGFloat(dim) / isz.width, CGFloat(dim) / isz.height)
        let w = isz.width * s, hgt = isz.height * s
        image.draw(in: NSRect(x: (CGFloat(dim) - w) / 2, y: (CGFloat(dim) - hgt) / 2,
                              width: w, height: hgt))
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = rep.cgImage else { return nil }
        return try? MTKTextureLoader(device: device).newTexture(cgImage: cg, options: [.SRGB: false])
    }
}
